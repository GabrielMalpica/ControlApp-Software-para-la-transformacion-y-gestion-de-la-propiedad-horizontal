import type { RequestHandler } from "express";
import crypto from "crypto";
import fs from "fs";
import { revisarEncabezadosFirma, validarFirmaControlApp } from "./pagos-woo-hmac.middleware";

function secretoWeb() {
  return process.env.CONTROLAPP_WEB_SECRET?.trim() || "";
}

export async function sha256DeArchivo(ruta: string): Promise<string> {
  const hash = crypto.createHash("sha256");
  await new Promise<void>((resolve, reject) => {
    fs.createReadStream(ruta)
      .on("data", (chunk) => hash.update(chunk))
      .on("end", () => resolve())
      .on("error", reject);
  });
  return hash.digest("hex");
}

/**
 * Antes de multer: canal configurado y encabezados de firma con un timestamp
 * vigente. Asi una peticion sin firma se rechaza sin escribir el archivo en
 * disco; la firma completa (que incluye el hash del archivo) se valida despues.
 */
export const prevalidarWebArchivosHmac: RequestHandler = (req, res, next) => {
  if (!secretoWeb()) {
    res.status(503).json({ message: "El canal de archivos de la pagina web no esta configurado" });
    return;
  }
  const rechazo = revisarEncabezadosFirma(req);
  if (rechazo) {
    res.status(rechazo.status).json({ message: rechazo.message });
    return;
  }
  next();
};

/**
 * Despues de multer: los plugins de WordPress (puente controlapp-archivos-drive)
 * firman `timestamp.nonce.POST.ruta.{sha256 del archivo}.{campo meta}` con
 * CONTROLAPP_WEB_SECRET y mandan el hash en X-ControlApp-Content-Sha256. Aqui
 * se recalcula el hash del archivo recibido, asi la firma cubre el contenido y
 * no solo los encabezados. Si algo no cuadra se borra el temporal.
 */
export const requireWebArchivosHmac: RequestHandler = async (req, res, next) => {
  const archivo = req.file;
  const descartar = () => (archivo ? fs.promises.unlink(archivo.path).catch(() => undefined) : undefined);
  try {
    if (!archivo) {
      res.status(400).json({ message: "Falta el archivo" });
      return;
    }
    const declarado = String(req.header("x-controlapp-content-sha256") ?? "").toLowerCase();
    const real = await sha256DeArchivo(archivo.path);
    if (!/^[a-f0-9]{64}$/.test(declarado) || declarado !== real) {
      await descartar();
      res.status(401).json({ message: "Firma invalida" });
      return;
    }

    const meta = typeof req.body?.meta === "string" ? req.body.meta : "";
    const rechazo = await validarFirmaControlApp(req, {
      secret: secretoWeb(),
      cuerpo: `${real}.${meta}`,
      prefijoNonce: "web:archivos:nonce:",
    });
    if (rechazo) {
      await descartar();
      res.status(rechazo.status).json({ message: rechazo.message });
      return;
    }
    next();
  } catch (error) {
    await descartar();
    next(error);
  }
};
