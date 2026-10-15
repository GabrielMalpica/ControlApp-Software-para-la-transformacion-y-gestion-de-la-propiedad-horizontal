import type { Request, RequestHandler } from "express";
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

export type RechazoFirma = { status: number; message: string };

/** Encabezados de firma presentes y timestamp dentro de la ventana (sin mirar la firma). */
export function revisarEncabezadosFirma(req: Request): RechazoFirma | null {
  const timestamp = String(req.header("x-controlapp-timestamp") ?? "");
  const nonce = String(req.header("x-controlapp-nonce") ?? "");
  const firma = String(req.header("x-controlapp-signature") ?? "");
  const ts = Number(timestamp);
  if (!timestamp || !nonce || !firma || !Number.isFinite(ts) || nonce.length > 100) {
    return { status: 401, message: "Firma invalida" };
  }
  if (Math.abs(Date.now() / 1000 - ts) > TOLERANCIA_SEGUNDOS) {
    return { status: 401, message: "Firma vencida" };
  }
  return null;
}

/**
 * Valida una firma de los plugins de WordPress (encabezados x-controlapp-*):
 * timestamp reciente, HMAC de `timestamp.nonce.METODO.ruta.cuerpo` y nonce de
 * un solo uso. Devuelve null si es valida o el rechazo a responder.
 */
export async function validarFirmaControlApp(
  req: Request,
  opciones: { secret: string; cuerpo: string; prefijoNonce: string },
): Promise<RechazoFirma | null> {
  const rechazo = revisarEncabezadosFirma(req);
  if (rechazo) return rechazo;

  const timestamp = String(req.header("x-controlapp-timestamp"));
  const nonce = String(req.header("x-controlapp-nonce"));
  const firma = String(req.header("x-controlapp-signature"));
  const esperada = firmarPagoWoo(opciones.secret, {
    timestamp,
    nonce,
    method: req.method,
    path: req.originalUrl.split("?")[0],
    body: opciones.cuerpo,
  });
  const a = Buffer.from(esperada, "utf8");
  const b = Buffer.from(firma, "utf8");
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
    return { status: 401, message: "Firma invalida" };
  }

  const clave = `${opciones.prefijoNonce}${nonce}`;
  if (await cacheGet<boolean>(clave)) {
    return { status: 401, message: "Solicitud repetida" };
  }
  await cacheSet(clave, true, NONCE_TTL_SEGUNDOS);
  return null;
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

    const rechazo = await validarFirmaControlApp(req, {
      secret,
      cuerpo: req.rawBody ? req.rawBody.toString("utf8") : "",
      prefijoNonce: "pagos:woo:nonce:",
    });
    if (rechazo) {
      res.status(rechazo.status).json({ message: rechazo.message });
      return;
    }
    next();
  } catch (error) {
    next(error);
  }
};
