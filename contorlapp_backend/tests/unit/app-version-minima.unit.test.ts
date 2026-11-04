// Versión mínima de la app Android: con APP_ANDROID_VERSION_MINIMA las
// versiones viejas reciben 426 (la app pide actualizar); la web nunca.
import express from "express";
import request from "supertest";

import { exigirVersionMinimaApp } from "../../src/middlewares/version-app.middleware";

function app() {
  const a = express();
  a.use(exigirVersionMinimaApp);
  a.get("/ping", (_req, res) => {
    res.json({ ok: true });
  });
  a.get("/recurso", (_req, res) => {
    res.json({ ok: true });
  });
  return a;
}

describe("versión mínima de la app Android", () => {
  afterEach(() => {
    delete process.env.APP_ANDROID_VERSION_MINIMA;
  });

  test("sin la variable no bloquea a nadie", async () => {
    const res = await request(app())
      .get("/recurso")
      .set("X-App-Plataforma", "android")
      .set("X-App-Version", "1");
    expect(res.status).toBe(200);
  });

  test("una versión vieja recibe 426 APP_DESACTUALIZADA", async () => {
    process.env.APP_ANDROID_VERSION_MINIMA = "5";
    const res = await request(app())
      .get("/recurso")
      .set("X-App-Plataforma", "android")
      .set("X-App-Version", "4");
    expect(res.status).toBe(426);
    expect(res.body).toMatchObject({ code: "APP_DESACTUALIZADA", versionMinima: 5 });
  });

  test("la versión mínima o mayor pasa, la web pasa y /ping siempre responde", async () => {
    process.env.APP_ANDROID_VERSION_MINIMA = "5";
    await request(app()).get("/recurso").set("X-App-Plataforma", "android").set("X-App-Version", "5").expect(200);
    await request(app()).get("/recurso").expect(200);
    await request(app()).get("/ping").set("X-App-Plataforma", "android").set("X-App-Version", "1").expect(200);
  });
});
