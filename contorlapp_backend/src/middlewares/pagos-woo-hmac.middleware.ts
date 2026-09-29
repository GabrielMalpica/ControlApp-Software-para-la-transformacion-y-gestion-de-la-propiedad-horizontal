import type { RequestHandler } from "express";
import crypto from "crypto";
import { cacheGet, cacheSet } from "../services/RedisService";

// Ventana en la que se acepta un pedido firmado y tiempo que se recuerda su
// nonce para rechazar reenvios (replay).
const TOLERANCIA_SEGUNDOS = 5 * 60;
const NONCE_TTL_SEGUNDOS = 10 * 60;

/** Firma que calcula el plugin: HMAC-SHA256 (hex) de
 * `timestamp.nonce.METODO.ruta.cuerpo` con CONTROLAPP_PAGOS_SECRET. */
export function firmarPagoWoo(
  secret: string,
  partes: { timestamp: string; nonce: string; method: string; path: string; body: string },
) {
  return crypto
    .createHmac("sha256", secret)
    .update(`${partes.timestamp}.${partes.nonce}.${partes.method.toUpperCase()}.${partes.path}.${partes.body}`)
    .digest("hex");
}

/**
 * Autentica al plugin de WooCommerce (controlapp-factus-pay) en las rutas
 * /commerce/pagos/woo/*, que no llevan JWT: firma HMAC + timestamp reciente +
 * nonce de un solo uso. Sin CONTROLAPP_PAGOS_SECRET responde 503.
 */
export const requirePagosWooHmac: RequestHandler = async (req, res, next) => {
  try {
    const secret = process.env.CONTROLAPP_PAGOS_SECRET;
    if (!secret) {
      res.status(503).json({ message: "El canal de pagos de la tienda no esta configurado" });
      return;
    }

    const timestamp = String(req.header("x-controlapp-timestamp") ?? "");
    const nonce = String(req.header("x-controlapp-nonce") ?? "");
    const firma = String(req.header("x-controlapp-signature") ?? "");
    const ts = Number(timestamp);
    if (!timestamp || !nonce || !firma || !Number.isFinite(ts) || nonce.length > 100) {
      res.status(401).json({ message: "Firma invalida" });
      return;
    }
    if (Math.abs(Date.now() / 1000 - ts) > TOLERANCIA_SEGUNDOS) {
      res.status(401).json({ message: "Firma vencida" });
      return;
    }

    const body = req.rawBody ? req.rawBody.toString("utf8") : "";
    const esperada = firmarPagoWoo(secret, {
      timestamp,
      nonce,
      method: req.method,
      path: req.originalUrl.split("?")[0],
      body,
    });
    const a = Buffer.from(esperada, "utf8");
    const b = Buffer.from(firma, "utf8");
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      res.status(401).json({ message: "Firma invalida" });
      return;
    }

    const clave = `pagos:woo:nonce:${nonce}`;
    if (await cacheGet<boolean>(clave)) {
      res.status(401).json({ message: "Solicitud repetida" });
      return;
    }
    await cacheSet(clave, true, NONCE_TTL_SEGUNDOS);
    next();
  } catch (error) {
    next(error);
  }
};
