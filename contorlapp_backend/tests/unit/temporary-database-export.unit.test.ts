import { EventEmitter } from "events";
import { PassThrough } from "stream";
import express from "express";
import request from "supertest";
import { createTemporaryDatabaseExportRouter } from "../../src/routes/TemporaryDatabaseExport";

function fakeSuccessfulDump(contents = "PGDMP-test") {
  const child = new EventEmitter() as any;
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.exitCode = null;
  child.kill = jest.fn(() => true);

  setImmediate(() => {
    child.emit("spawn");
    child.stdout.end(Buffer.from(contents));
    child.stderr.end();
    child.exitCode = 0;
    child.emit("close", 0, null);
  });

  return child;
}

function testApp(
  overrides: NodeJS.ProcessEnv = {},
  startDump = jest.fn(() => fakeSuccessfulDump()),
) {
  const app = express();
  app.use(
    "/internal/temporary/database-export",
    createTemporaryDatabaseExportRouter({
      env: {
        TEMP_DB_EXPORT_ENABLED: "true",
        TEMP_DB_EXPORT_TOKEN: "a".repeat(43),
        TEMP_DB_EXPORT_EXPIRES_AT: "2026-08-13T20:00:00.000Z",
        DATABASE_URL: "postgresql://production.example/controlapp",
        ...overrides,
      },
      now: () => new Date("2026-08-13T19:00:00.000Z"),
      startDump,
    }),
  );
  return { app, startDump };
}

describe("exportacion temporal de base de datos", () => {
  test("permanece oculta cuando no esta habilitada", async () => {
    const { app, startDump } = testApp({ TEMP_DB_EXPORT_ENABLED: "false" });

    await request(app)
      .get("/internal/temporary/database-export")
      .set("Authorization", `Bearer ${"a".repeat(43)}`)
      .expect(404);

    expect(startDump).not.toHaveBeenCalled();
  });

  test("permanece oculta despues de la caducidad", async () => {
    const { app, startDump } = testApp({
      TEMP_DB_EXPORT_EXPIRES_AT: "2026-08-13T18:59:59.000Z",
    });

    await request(app)
      .get("/internal/temporary/database-export")
      .set("Authorization", `Bearer ${"a".repeat(43)}`)
      .expect(404);

    expect(startDump).not.toHaveBeenCalled();
  });

  test("rechaza configuraciones que pretendan dejarla activa mas de 24 horas", async () => {
    const { app, startDump } = testApp({
      TEMP_DB_EXPORT_EXPIRES_AT: "2026-08-15T19:00:00.000Z",
    });

    await request(app)
      .get("/internal/temporary/database-export")
      .set("Authorization", `Bearer ${"a".repeat(43)}`)
      .expect(404);

    expect(startDump).not.toHaveBeenCalled();
  });

  test("rechaza un token incorrecto", async () => {
    const { app, startDump } = testApp();

    await request(app)
      .get("/internal/temporary/database-export")
      .set("Authorization", `Bearer ${"b".repeat(43)}`)
      .expect(401);

    expect(startDump).not.toHaveBeenCalled();
  });

  test("transmite el dump sin exponer DATABASE_URL como argumento", async () => {
    const { app, startDump } = testApp();

    const response = await request(app)
      .get("/internal/temporary/database-export")
      .set("Authorization", `Bearer ${"a".repeat(43)}`)
      .buffer(true)
      .parse((res, callback) => {
        const chunks: Buffer[] = [];
        res.on("data", (chunk) => chunks.push(Buffer.from(chunk)));
        res.on("end", () => callback(null, Buffer.concat(chunks)));
      })
      .expect(200)
      .expect("Content-Type", "application/octet-stream")
      .expect("Cache-Control", "no-store, max-age=0");

    expect(response.body.toString()).toBe("PGDMP-test");
    expect(startDump).toHaveBeenCalledWith("postgresql://production.example/controlapp");
  });
});
