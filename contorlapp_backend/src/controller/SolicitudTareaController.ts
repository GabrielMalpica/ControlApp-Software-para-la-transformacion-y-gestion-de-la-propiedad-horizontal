// src/controllers/SolicitudTareaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { SolicitudTareaService } from "../services/SolicitudTareaServices";

const SolicitudIdParam = z.object({ solicitudId: z.coerce.number().int().positive() });
const RechazarBody = z.object({ observacion: z.string().min(1).max(500) });

export class SolicitudTareaController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /solicitudes-tarea/:solicitudId/aprobar
  aprobar: RequestHandler = async (req, res, next) => {
    try {
      const { solicitudId } = SolicitudIdParam.parse(req.params);
      const service = new SolicitudTareaService(this.prisma, solicitudId);
      await service.aprobar();
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /solicitudes-tarea/:solicitudId/rechazar
  rechazar: RequestHandler = async (req, res, next) => {
    try {
      const { solicitudId } = SolicitudIdParam.parse(req.params);
      const body = RechazarBody.parse(req.body);
      const service = new SolicitudTareaService(this.prisma, solicitudId);
      await service.rechazar(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /solicitudes-tarea/:solicitudId/estado
  estadoActual: RequestHandler = async (req, res, next) => {
    try {
      const { solicitudId } = SolicitudIdParam.parse(req.params);
      const service = new SolicitudTareaService(this.prisma, solicitudId);
      const estado = await service.estadoActual();
      res.json({ estado });
    } catch (err) { next(err); }
  };
}
