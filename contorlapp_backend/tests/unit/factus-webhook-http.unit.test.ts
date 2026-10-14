import express, { type ErrorRequestHandler, type Request, type Response } from "express";
import request from "supertest";

const recibir = jest.fn();
const procesar = jest.fn();
jest.mock("../../src/services/pagos/factusWebhookInstance", () => ({
  factusWebhook: {
    recibir: (...args: unknown[]) => recibir(...args),
    procesar: (...args: unknown[]) => procesar(...args),
  },
}));

import { FactusWebhookController } from "../../src/controller/FactusWebhookController";
import { authRequiredUnlessPublic } from "../../src/middlewares/auth.middleware";

const RUTA = "/commerce/webhooks/factus-pay";

// Misma configuracion que src/index.ts: parser propio de 256 KB para la ruta
// (antes del general de 1 MB), cuerpo crudo guardado y guard de JWT con la
// ruta en la lista de publicas.
function crearApp() {
  const app = express();
  const guardarRawBody = (req: Request, _res: Response, buf: Buffer) => {
    req.rawBody = buf;
  };
  app.use(RUTA, express.json({ limit: "256kb", verify: guardarRawBody }));
  app.use(express.json({ limit: "1mb", verify: guardarRawBody }));
  app.use(authRequiredUnlessPublic);
  app.post(RUTA, new FactusWebhookController().recibir);
  const errores: ErrorRequestHandler = (err, _req, res, _next) => {
    res.status(typeof err?.status === "number" ? err.status : 500).json({ ok: false });
  };
  app.use(errores);
  return app;
}

beforeEach(() => {
  recibir.mockReset();
  procesar.mockReset().mockResolvedValue(undefined);
});

describe("POST /commerce/webhooks/factus-pay", () => {
  test("es publica (sin Bearer) y pasa la llave del query string al servicio", async () => {
    recibir.mockResolvedValue({ status: 200, body: { received: true }, webhookId: 9 });

    const res = await request(crearApp())
      .post(`${RUTA}?key=la-llave`)
      .send({ data: { reference_code: "CA-1", amount: 50000, status: "paid" } });

    expect(res.status).toBe(200);
    expect(res.body).toEqual({ received: true });
    expect(recibir).toHaveBeenCalledWith(
      expect.objectContaining({ key: "la-llave", body: expect.any(Object), rawBody: expect.any(Buffer) }),
    );
  });

  test("procesa el aviso despues de responder", async () => {
    recibir.mockResolvedValue({ status: 200, body: { received: true }, webhookId: 9 });

    await request(crearApp()).post(`${RUTA}?key=x`).send({ data: {} });
    await new Promise((resolve) => setImmediate(resolve));

    expect(procesar).toHaveBeenCalledWith(9);
  });

  test("devuelve tal cual el rechazo del servicio (401) y no procesa nada", async () => {
    recibir.mockResolvedValue({ status: 401, body: { message: "Llave invalida" } });

    const res = await request(crearApp()).post(`${RUTA}?key=mala`).send({ data: {} });
    await new Promise((resolve) => setImmediate(resolve));

    expect(res.status).toBe(401);
    expect(procesar).not.toHaveBeenCalled();
  });

  test("si no se pudo guardar el aviso (base de datos caida) responde 5xx para que Factus reintente", async () => {
    recibir.mockRejectedValue(new Error("db caida"));

    const res = await request(crearApp()).post(`${RUTA}?key=x`).send({ data: {} });

    expect(res.status).toBeGreaterThanOrEqual(500);
  });

  test("un cuerpo de mas de 256 KB se rechaza antes de llegar al servicio", async () => {
    const res = await request(crearApp())
      .post(`${RUTA}?key=x`)
      .set("Content-Type", "application/json")
      .send(JSON.stringify({ data: { qr: "A".repeat(300 * 1024) } }));

    expect(res.status).toBe(413);
    expect(recibir).not.toHaveBeenCalled();
  });

  test("JSON invalido: 400 sin llegar al servicio", async () => {
    const res = await request(crearApp())
      .post(`${RUTA}?key=x`)
      .set("Content-Type", "application/json")
      .send("{no es json");

    expect(res.status).toBe(400);
    expect(recibir).not.toHaveBeenCalled();
  });
});
