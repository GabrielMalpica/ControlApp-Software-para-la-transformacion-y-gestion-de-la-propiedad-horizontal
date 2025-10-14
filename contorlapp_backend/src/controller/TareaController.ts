// src/controllers/TareaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { TareaService } from "../services/TareaServices";

const TareaIdParam = z.object({ tareaId: z.coerce.number().int().positive() });

const EvidenciaBody = z.object({ imagen: z.string().min(1) });
const AprobarBody = z.object({ supervisorId: z.number().int().positive() });
const RechazarBody = z.object({
  supervisorId: z.number().int().positive(),
  observacion: z.string().min(3).max(500),
});

export class TareaController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /tareas/:tareaId/evidencias
  agregarEvidencia: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const body = EvidenciaBody.parse(req.body);
      const service = new TareaService(this.prisma, tareaId);
      await service.agregarEvidencia(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /tareas/:tareaId/iniciar
  iniciarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = new TareaService(this.prisma, tareaId);
      await service.iniciarTarea();
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /tareas/:tareaId/no-completada
  marcarNoCompletada: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = new TareaService(this.prisma, tareaId);
      await service.marcarNoCompletada();
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /tareas/:tareaId/aprobar
  aprobarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const { supervisorId } = AprobarBody.parse(req.body);
      const service = new TareaService(this.prisma, tareaId);
      await service.aprobarTarea({ supervisorId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /tareas/:tareaId/rechazar
  rechazarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const body = RechazarBody.parse(req.body);
      const service = new TareaService(this.prisma, tareaId);
      await service.rechazarTarea(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /tareas/:tareaId/resumen
  resumen: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = new TareaService(this.prisma, tareaId);
      const text = await service.resumen();
      res.json({ resumen: text });
    } catch (err) { next(err); }
  };
}
