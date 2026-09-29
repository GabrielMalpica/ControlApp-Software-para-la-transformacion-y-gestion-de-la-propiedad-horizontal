import type { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { CommerceLifecycleService } from "../services/CommerceLifecycleService";
import { pagoService } from "../services/pagos/pagoServiceInstance";
import { PagoWooService } from "../services/pagos/PagoWooService";

const service = new PagoWooService(prisma, pagoService, new CommerceLifecycleService(prisma));

function referencia(value: unknown) {
  const ref = String(value ?? "");
  return /^[A-Za-z0-9-]{1,100}$/.test(ref) ? ref : null;
}

/** Rutas para el plugin de WooCommerce, autenticadas con HMAC (ver
 * requirePagosWooHmac), no con un JWT de ControlApp. */
export class PagoWooController {
  crear: RequestHandler = async (req, res, next) => {
    try {
      res.status(201).json(await service.crearCobro(req.body));
    } catch (error) {
      next(error);
    }
  };

  obtener: RequestHandler = async (req, res, next) => {
    try {
      const ref = referencia(req.params.referenceCode);
      if (!ref) {
        res.status(404).json({ message: "Cobro no encontrado" });
        return;
      }
      res.json(await service.obtenerCobro(ref));
    } catch (error) {
      next(error);
    }
  };

  verificar: RequestHandler = async (req, res, next) => {
    try {
      const ref = referencia(req.params.referenceCode);
      if (!ref) {
        res.status(404).json({ message: "Cobro no encontrado" });
        return;
      }
      res.json(await service.verificarCobro(ref));
    } catch (error) {
      next(error);
    }
  };
}
