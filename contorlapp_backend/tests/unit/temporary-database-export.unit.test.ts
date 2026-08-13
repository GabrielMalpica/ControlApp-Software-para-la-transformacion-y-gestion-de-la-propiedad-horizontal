import { EventEmitter } from "events";
import { PassThrough } from "stream";
import express from "express";
import request from "supertest";
import {
  createTemporaryDatabaseExportRouter,
  databaseUrlForPgDump,
  pgDumpConnectionForDatabaseUrl,
} from "../../src/routes/TemporaryDatabaseExport";

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

function fakeFailedDump(stderr: string) {
  const child = new EventEmitter() as any;
  child.stdout = new PassThrough();
  child.stderr = new PassThrough();
  child.exitCode = null;
  child.kill = jest.fn(() => true);

  setImmediate(() => {
    child.emit("spawn");
    child.stderr.end(stderr);
    child.stdout.end();
    child.exitCode = 1;
    child.emit("close", 1, null);
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
  test("elimina opciones de Prisma y conserva opciones SSL para libpq", () => {
    const result = databaseUrlForPgDump(
      "postgresql://user:secret@db.internal/app?connection_limit=10&pool_timeout=20&pgbouncer=true&schema=public&sslmode=require",
    );

    const url = new URL(result);
    expect(url.searchParams.get("sslmode")).toBe("require");
    expect(url.searchParams.has("connection_limit")).toBe(false);
    expect(url.searchParams.has("pool_timeout")).toBe(false);
    expect(url.searchParams.has("pgbouncer")).toBe(false);
    expect(url.searchParams.has("schema")).toBe(false);
  });

  test("entrega la conexion a pg_dump mediante variables nativas de libpq", () => {
    expect(
      pgDumpConnectionForDatabaseUrl(
        "postgresql://usuario:contra%20segura@db.internal:5444/controlapp?connection_limit=10&pool_timeout=20&sslmode=require",
      ),
    ).toEqual({
      PGHOST: "db.internal",
      PGPORT: "5444",
      PGDATABASE: "controlapp",
      PGUSER: "usuario",
      PGPASSWORD: "contra segura",
      PGSSLMODE: "require",
    });
  });

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
    expect(startDump).toHaveBeenCalledWith({
      PGHOST: "production.example",
      PGPORT: "5432",
      PGDATABASE: "controlapp",
    });
  });

  test("informa una incompatibilidad de versiones sin exponer la conexion", async () => {
    const consoleError = jest.spyOn(console, "error").mockImplementation(() => undefined);
    const startDump = jest.fn(() =>
      fakeFailedDump(
        'pg_dump: error: server version: 18.1; pg_dump version: 17.6\npg_dump: error: aborting because of server version mismatch',
      ),
    );
    const { app } = testApp({}, startDump);

    try {
      const response = await request(app)
        .get("/internal/temporary/database-export")
        .set("Authorization", `Bearer ${"a".repeat(43)}`)
        .expect(500);

      expect(response.body).toEqual({
        message: "No se pudo generar el respaldo",
        reason: "Version incompatible: PostgreSQL 18.1, pg_dump 17.6",
      });
      expect(JSON.stringify(response.body)).not.toContain("production.example");
    } finally {
      consoleError.mockRestore();
    }
  });
});
