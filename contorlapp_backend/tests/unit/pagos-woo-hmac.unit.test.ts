import express from "express";
import request from "supertest";

const nonces = new Set<string>();
jest.mock("../../src/services/RedisService", () => ({
  cacheGet: jest.fn(async (key: string) => (nonces.has(key) ? true : null)),
  cacheSet: jest.fn(async (key: string) => {
    nonces.add(key);
  }),
}));

import { firmarPagoWoo, requirePagosWooHmac } from "../../src/middlewares/pagos-woo-hmac.middleware";

const SECRET = "secreto-pagos-test";

function crearApp() {
  const app = express();
  app.use(express.json({ verify: (req, _res, buf) => ((req as any).rawBody = buf) }));
  const ok: express.RequestHandler = (_req, res) => {
    res.json({ ok: true });
  };
  app.post("/commerce/pagos/woo/cobros", requirePagosWooHmac, ok);
  app.get("/commerce/pagos/woo/cobros/:ref", requirePagosWooHmac, ok);
  return app;
}

function firmado(opts: {
  method?: "post" | "get";
  path?: string;
  body?: object;
  ts?: number;
  nonce?: string;
  secret?: string;
}) {
  const method = opts.method ?? "post";
  const path = opts.path ?? "/commerce/pagos/woo/cobros";
  const cuerpo = opts.body ? JSON.stringify(opts.body) : "";
  const timestamp = String(opts.ts ?? Math.floor(Date.now() / 1000));
  const nonce = opts.nonce ?? `n-${Math.random()}`;
  const firma = firmarPagoWoo(opts.secret ?? SECRET, { timestamp, nonce, method, path, body: cuerpo });
  const req = request(crearApp())
    [method](path)
    .set("X-ControlApp-Timestamp", timestamp)
    .set("X-ControlApp-Nonce", nonce)
    .set("X-ControlApp-Signature", firma);
  return cuerpo ? req.set("Content-Type", "application/json").send(cuerpo) : req;
}

describe("requirePagosWooHmac", () => {
  const original = process.env.CONTROLAPP_PAGOS_SECRET;
  beforeEach(() => {
    process.env.CONTROLAPP_PAGOS_SECRET = SECRET;
    nonces.clear();
  });
  afterAll(() => {
    if (original === undefined) delete process.env.CONTROLAPP_PAGOS_SECRET;
    else process.env.CONTROLAPP_PAGOS_SECRET = original;
  });

  test("sin secreto configurado responde 503", async () => {
    delete process.env.CONTROLAPP_PAGOS_SECRET;
    expect((await firmado({ body: { a: 1 } })).status).toBe(503);
  });

  test("firma valida pasa (POST con cuerpo y GET sin cuerpo)", async () => {
    expect((await firmado({ body: { wooOrderId: "5" } })).status).toBe(200);
    expect((await firmado({ method: "get", path: "/commerce/pagos/woo/cobros/WC-1" })).status).toBe(200);
  });

  test("cuerpo alterado -> 401", async () => {
    const ts = String(Math.floor(Date.now() / 1000));
    const firma = firmarPagoWoo(SECRET, {
      timestamp: ts,
      nonce: "x1",
      method: "post",
      path: "/commerce/pagos/woo/cobros",
      body: '{"a":1}',
    });
    const res = await request(crearApp())
      .post("/commerce/pagos/woo/cobros")
      .set("Content-Type", "application/json")
      .set("X-ControlApp-Timestamp", ts)
      .set("X-ControlApp-Nonce", "x1")
      .set("X-ControlApp-Signature", firma)
      .send('{"a":2}');
    expect(res.status).toBe(401);
  });

  test("firmado con otro secreto -> 401", async () => {
    expect((await firmado({ body: { a: 1 }, secret: "otro" })).status).toBe(401);
  });

  test("la firma de una ruta no sirve para otra", async () => {
    const ts = String(Math.floor(Date.now() / 1000));
    const firma = firmarPagoWoo(SECRET, {
      timestamp: ts,
      nonce: "x2",
      method: "get",
      path: "/commerce/pagos/woo/cobros/WC-1",
      body: "",
    });
    const res = await request(crearApp())
      .get("/commerce/pagos/woo/cobros/WC-2")
      .set("X-ControlApp-Timestamp", ts)
      .set("X-ControlApp-Nonce", "x2")
      .set("X-ControlApp-Signature", firma);
    expect(res.status).toBe(401);
  });

  test("timestamp fuera de la ventana de 5 minutos -> 401", async () => {
    const res = await firmado({ body: { a: 1 }, ts: Math.floor(Date.now() / 1000) - 10 * 60 });
    expect(res.status).toBe(401);
  });

  test("reenviar la misma solicitud (mismo nonce) -> 401", async () => {
    const ts = String(Math.floor(Date.now() / 1000));
    const firma = firmarPagoWoo(SECRET, {
      timestamp: ts,
      nonce: "repetido",
      method: "get",
      path: "/commerce/pagos/woo/cobros/WC-1",
      body: "",
    });
    const enviar = () =>
      request(crearApp())
        .get("/commerce/pagos/woo/cobros/WC-1")
        .set("X-ControlApp-Timestamp", ts)
        .set("X-ControlApp-Nonce", "repetido")
        .set("X-ControlApp-Signature", firma);
    expect((await enviar()).status).toBe(200);
    expect((await enviar()).status).toBe(401);
  });

  test("faltan cabeceras -> 401", async () => {
    const res = await request(crearApp()).post("/commerce/pagos/woo/cobros").send({});
    expect(res.status).toBe(401);
  });
});
