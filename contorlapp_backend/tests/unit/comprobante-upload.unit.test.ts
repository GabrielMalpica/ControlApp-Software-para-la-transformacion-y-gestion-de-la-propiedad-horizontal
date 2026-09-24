import fs from "fs";
import express from "express";
import request from "supertest";
import { uploadComprobante, uploadFotoInventario } from "../../src/middlewares/upload_evidencias";

const MB = 1024 * 1024;

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const PDF_MAGIC = Buffer.from("%PDF-1.4\n");

function archivo(magic: Buffer, megas: number) {
  return Buffer.concat([magic, Buffer.alloc(Math.floor(megas * MB) - magic.length, 1)]);
}

// Responde como el manejador de errores real de src/index.ts: los errores con
// { ok: false, status, message } salen con ese status y mensaje.
function crearApp(middlewares: express.RequestHandler[]) {
  const app = express();
  app.post("/subir", ...middlewares, async (req, res) => {
    const file = (req as any).file as Express.Multer.File;
    const size = file.size;
    await fs.promises.unlink(file.path).catch(() => undefined);
    res.json({ ok: true, size });
  });
  app.use(((err, _req, res, _next) => {
    if (err && err.ok === false) {
      res.status(err.status).json({ ok: false, message: err.message });
      return;
    }
    res.status(400).json({ ok: false, message: err.message });
  }) as express.ErrorRequestHandler);
  return app;
}

describe("subida de comprobantes de pago", () => {
  const app = crearApp(uploadComprobante.single("comprobante"));

  test.each([
    ["captura PNG de 6 MB (antes fallaba)", PNG_MAGIC, "captura.png", "image/png", 6],
    ["captura PNG de 12 MB (mas del tope viejo de 10 MB)", PNG_MAGIC, "captura.png", "image/png", 12],
    ["PDF de 8 MB", PDF_MAGIC, "comprobante.pdf", "application/pdf", 8],
    ["PNG de 24 MB (justo bajo el tope)", PNG_MAGIC, "grande.png", "image/png", 24],
  ])("acepta %s", async (_nombre, magic, filename, contentType, megas) => {
    const res = await request(app)
      .post("/subir")
      .attach("comprobante", archivo(magic, megas), { filename, contentType });

    expect(res.status).toBe(200);
    expect(res.body.size).toBeGreaterThan(5 * MB);
  });

  test("rechaza mas de 25 MB con un mensaje claro que menciona el limite real", async () => {
    const res = await request(app)
      .post("/subir")
      .attach("comprobante", archivo(PNG_MAGIC, 26), {
        filename: "enorme.png",
        contentType: "image/png",
      });

    expect(res.status).toBe(413);
    expect(res.body.message).toContain("25 MB");
    expect(res.body.message).not.toContain("fotograf");
  });

  test("rechaza tipos que no son JPG, PNG o PDF", async () => {
    const res = await request(app)
      .post("/subir")
      .attach("comprobante", Buffer.from("MZ..."), {
        filename: "virus.exe",
        contentType: "application/x-msdownload",
      });

    expect(res.status).toBe(400);
    expect(res.body.message).toContain("JPG, JPEG, PNG o PDF");
  });

  test("rechaza un archivo cuyo contenido no coincide con su extension", async () => {
    const res = await request(app)
      .post("/subir")
      .attach("comprobante", Buffer.from("no soy un png de verdad"), {
        filename: "falso.png",
        contentType: "image/png",
      });

    expect(res.status).toBe(400);
    expect(res.body.message).toContain("no coincide");
  });

  test("las fotos de inventario conservan su limite de 5 MB", async () => {
    const appFotos = crearApp(uploadFotoInventario.single("foto"));
    const res = await request(appFotos)
      .post("/subir")
      .attach("foto", archivo(PNG_MAGIC, 6), { filename: "foto.png", contentType: "image/png" });

    // Multer lo rechaza con su error de limite (el manejador real de la app
    // lo convierte en 413); aqui basta comprobar que no paso.
    expect(res.status).not.toBe(200);
  });
});
