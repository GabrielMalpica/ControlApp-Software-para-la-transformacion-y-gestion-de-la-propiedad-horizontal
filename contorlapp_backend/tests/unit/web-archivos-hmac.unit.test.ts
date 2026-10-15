import crypto from "crypto";
import express from "express";
import request from "supertest";

const nonces = new Set<string>();
jest.mock("../../src/services/RedisService", () => ({
  cacheGet: jest.fn(async (key: string) => (nonces.has(key) ? true : null)),
  cacheSet: jest.fn(async (key: string) => {
    nonces.add(key);
  }),
}));

import { firmarPagoWoo } from "../../src/middlewares/pagos-woo-hmac.middleware";
import { uploadArchivoWeb } from "../../src/middlewares/upload_evidencias";
import {
  prevalidarWebArchivosHmac,
  requireWebArchivosHmac,
} from "../../src/middlewares/web-archivos-hmac.middleware";

const SECRET = "secreto-web-test";
const RUTA = "/commerce/web/archivos";
const PNG = Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), Buffer.from("contenido")]);
const META = JSON.stringify({ caso: "trabajador", carpeta: "Ana Ruiz - #7", nombre: "cedula.png" });

function crearApp() {
  const app = express();
  app.post(RUTA, prevalidarWebArchivosHmac, ...uploadArchivoWeb.single("archivo"), requireWebArchivosHmac, (req, res) => {
    res.json({ ok: true, meta: req.body.meta });
  });
  return app;
}

const sha = (b: Buffer) => crypto.createHash("sha256").update(b).digest("hex");

function enviar(opts: {
  archivo?: Buffer;
  hashDeclarado?: string;
  metaFirmado?: string;
  metaEnviado?: string;
  ts?: number;
  nonce?: string;
  sinFirma?: boolean;
}) {
  const archivo = opts.archivo ?? PNG;
  const hashDeclarado = opts.hashDeclarado ?? sha(PNG);
  const timestamp = String(opts.ts ?? Math.floor(Date.now() / 1000));
  const nonce = opts.nonce ?? `n-${Math.random()}`;
  const firma = firmarPagoWoo(SECRET, {
    timestamp,
    nonce,
    method: "POST",
    path: RUTA,
    body: `${hashDeclarado}.${opts.metaFirmado ?? META}`,
  });
  let req = request(crearApp()).post(RUTA);
  if (!opts.sinFirma) {
    req = req
      .set("X-ControlApp-Timestamp", timestamp)
      .set("X-ControlApp-Nonce", nonce)
      .set("X-ControlApp-Signature", firma)
      .set("X-ControlApp-Content-Sha256", hashDeclarado);
  }
  return req.field("meta", opts.metaEnviado ?? META).attach("archivo", archivo, {
    filename: "cedula.png",
    contentType: "image/png",
  });
}

describe("firma de archivos de la pagina web", () => {
  const original = process.env.CONTROLAPP_WEB_SECRET;
  beforeEach(() => {
    process.env.CONTROLAPP_WEB_SECRET = SECRET;
    nonces.clear();
  });
  afterAll(() => {
    if (original === undefined) delete process.env.CONTROLAPP_WEB_SECRET;
    else process.env.CONTROLAPP_WEB_SECRET = original;
  });

  test("sin secreto configurado responde 503", async () => {
    delete process.env.CONTROLAPP_WEB_SECRET;
    expect((await enviar({})).status).toBe(503);
  });

  test("archivo y meta firmados pasan", async () => {
    const res = await enviar({});
    expect(res.status).toBe(200);
    expect(res.body.meta).toBe(META);
  });

  test("sin encabezados de firma se rechaza antes de leer el archivo", async () => {
    expect((await enviar({ sinFirma: true })).status).toBe(401);
  });

  test("archivo distinto al firmado -> 401", async () => {
    const otro = Buffer.concat([PNG, Buffer.from("x")]);
    expect((await enviar({ archivo: otro })).status).toBe(401);
  });

  test("meta alterado -> 401", async () => {
    const alterado = JSON.stringify({ caso: "conjunto", carpeta: "Otro", nombre: "cedula.png" });
    expect((await enviar({ metaEnviado: alterado })).status).toBe(401);
  });

  test("firma vencida -> 401", async () => {
    expect((await enviar({ ts: Math.floor(Date.now() / 1000) - 3600 })).status).toBe(401);
  });

  test("el mismo nonce no se acepta dos veces", async () => {
    expect((await enviar({ nonce: "repetido" })).status).toBe(200);
    expect((await enviar({ nonce: "repetido" })).status).toBe(401);
  });
});
