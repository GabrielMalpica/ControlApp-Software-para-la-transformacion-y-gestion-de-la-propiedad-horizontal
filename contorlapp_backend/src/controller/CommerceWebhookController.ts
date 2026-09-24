import type { RequestHandler } from "express";
import crypto from "crypto";
import { prisma } from "../db/prisma";
import { CommerceLifecycleService } from "../services/CommerceLifecycleService";

const service = new CommerceLifecycleService(prisma);

function firmaValida(rawBody: Buffer | undefined, header: string | undefined, secret: string) {
  if (!rawBody || !header) return false;
  const esperada = crypto.createHmac("sha256", secret).update(rawBody).digest("base64");
  const recibida = Buffer.from(header, "utf8");
  const esperadaBuf = Buffer.from(esperada, "utf8");
  if (recibida.length !== esperadaBuf.length) return false;
  return crypto.timingSafeEqual(recibida, esperadaBuf);
}

export class CommerceWebhookController {
  /**
   * Recibe el webhook "Order updated" que se configura a mano en WooCommerce
   * (wp-admin -> WooCommerce -> Ajustes -> Avanzado -> Webhooks). No usa JWT
   * -WooCommerce no tiene un token de ControlApp- sino la firma HMAC propia
   * de WooCommerce (X-WC-Webhook-Signature), calculada con el secreto que se
   * define al crear el webhook y que debe copiarse a WOOCOMMERCE_WEBHOOK_SECRET.
   */
  ordenActualizada: RequestHandler = async (req, res, next) => {
    try {
      // Al guardar el webhook en wp-admin, WooCommerce hace un "ping" de
      // prueba: POST form-urlencoded ("webhook_id=N") y SIN firma. Si no recibe
      // 200, deja el webhook desactivado. Es inocuo -no procesa nada ni toca
      // ningun pedido-, asi que se responde antes de exigir la firma.
      if (!req.header("x-wc-webhook-signature") && req.is("application/x-www-form-urlencoded")) {
        res.status(200).json({ ok: true });
        return;
      }

      const secret = process.env.WOOCOMMERCE_WEBHOOK_SECRET;
      if (!secret) {
        // No configurado todavia: no se puede verificar nada, se rechaza en
        // vez de confiar en payloads sin firma.
        res.status(503).json({ message: "Webhook no configurado" });
        return;
      }

      const firma = req.header("x-wc-webhook-signature");
      if (!firmaValida(req.rawBody, firma, secret)) {
        res.status(401).json({ message: "Firma invalida" });
        return;
      }

      // Payload firmado pero sin pedido (p. ej. otros topics): nada que procesar.
      const payload = req.body as { id?: number; status?: string } | undefined;
      if (!payload?.id) {
        res.status(200).json({ ok: true });
        return;
      }

      // El servicio decide que hacer con cada estado (ver
      // aplicarEstadoDesdeWoo): avanza el pedido si es uno de los que el
      // equipo maneja desde wp-admin, o solo lo registra si es ajeno.
      const status = String(payload.status ?? "");
      if (status) await service.aplicarEstadoDesdeWoo(String(payload.id), status);

      res.status(200).json({ ok: true });
    } catch (error) {
      next(error);
    }
  };
}
