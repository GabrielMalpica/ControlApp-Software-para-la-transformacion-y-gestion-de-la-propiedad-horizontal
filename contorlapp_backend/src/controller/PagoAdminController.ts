import type { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { CommerceAccessService } from "../services/CommerceAccessService";
import { ejecutarConciliacion, ultimoReporteConciliacion } from "../services/pagos/conciliacionInstance";
import { PagoAdminService } from "../services/pagos/PagoAdminService";

const service = new PagoAdminService(prisma);
const access = new CommerceAccessService(prisma);
const CobroParamDTO = z.object({ cobroId: z.coerce.number().int().positive() });

/** Panel de pagos para gerente y jefe de operaciones (rutas /commerce/pagos). */
export class PagoAdminController {
  private actor = async (userId: string) => access.getActor(userId);

  listar: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.listar(await this.actor(req.user!.sub), req.query));
    } catch (error) {
      next(error);
    }
  };

  conteo: RequestHandler = async (req, res, next) => {
    try {
      res.json({ requierenAccion: await service.contarRequierenAccion(await this.actor(req.user!.sub)) });
    } catch (error) {
      next(error);
    }
  };

  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { cobroId } = CobroParamDTO.parse(req.params);
      res.json(await service.obtener(await this.actor(req.user!.sub), cobroId));
    } catch (error) {
      next(error);
    }
  };

  resolver: RequestHandler = async (req, res, next) => {
    try {
      const { cobroId } = CobroParamDTO.parse(req.params);
      res.json(await service.resolver(await this.actor(req.user!.sub), cobroId, req.body));
    } catch (error) {
      next(error);
    }
  };

  reporteRecaudo: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.reporteRecaudo(await this.actor(req.user!.sub), req.query));
    } catch (error) {
      next(error);
    }
  };

  ultimaConciliacion: RequestHandler = async (_req, res, next) => {
    try {
      res.json({ reporte: await ultimoReporteConciliacion() });
    } catch (error) {
      next(error);
    }
  };

  conciliar: RequestHandler = async (_req, res, next) => {
    try {
      res.json({ reporte: await ejecutarConciliacion() });
    } catch (error) {
      next(error);
    }
  };
}
