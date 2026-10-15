import type { Request, RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { CommerceAccessService } from "../services/CommerceAccessService";
import { saldoServicio } from "../services/pagos/saldoServicioInstance";

const access = new CommerceAccessService(prisma);
const SaldoParamDTO = z.object({ saldoId: z.coerce.number().int().positive() });

const responder =
  (handler: (req: Request) => Promise<unknown>, status = 200): RequestHandler =>
  async (req, res, next) => {
    try {
      res.status(status).json(await handler(req));
    } catch (error) {
      next(error);
    }
  };

/**
 * Saldo de servicios pagados con anticipo (ver SaldoServicioService):
 * - tienda: plugin controlapp-factus-pay, firmado con HMAC (sin JWT);
 * - app: el cliente ve y paga SUS saldos;
 * - panel "Clientes en mora": gerente y jefe de operaciones.
 */
export class SaldoServicioController {
  // Tienda (HMAC)
  servicioTerminado = responder((req) => saldoServicio.registrarServicioTerminado(req.body));
  consultarTienda = responder((req) => saldoServicio.obtenerParaTienda(req.body));
  cobrarTienda = responder((req) => saldoServicio.cobrarParaTienda(req.body), 201);
  moraTienda = responder((req) => saldoServicio.consultarMoraTienda(req.body));

  // App (dueno del saldo)
  listarMios = responder((req) => saldoServicio.listarMios(req.user!.sub));
  obtenerMio = responder((req) => saldoServicio.obtenerMio(req.user!.sub, SaldoParamDTO.parse(req.params).saldoId));
  pagarMio = responder((req) => saldoServicio.pagarMio(req.user!.sub, SaldoParamDTO.parse(req.params).saldoId), 201);
  verificarMio = responder((req) =>
    saldoServicio.verificarMio(req.user!.sub, SaldoParamDTO.parse(req.params).saldoId),
  );

  // Panel
  listarMora = responder((req) => saldoServicio.listarMora(req.query));
  resolver = responder(async (req) =>
    saldoServicio.resolverPorFuera(
      await access.getActor(req.user!.sub),
      SaldoParamDTO.parse(req.params).saldoId,
      req.body,
    ),
  );
}
