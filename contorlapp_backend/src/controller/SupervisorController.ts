// src/controllers/SupervisorController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { SupervisorService } from "../services/SupervisorServices";

const SupervisorIdParam = z.object({ supervisorId: z.coerce.number().int().positive() });
const TareaIdParam = z.object({ tareaId: z.coerce.number().int().positive() });
const RechazarBody = z.object({ observaciones: z.string().min(3).max(500) });

export class SupervisorController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /supervisores/:supervisorId/tareas/:tareaId/recibir
  recibirTareaFinalizada: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = new SupervisorService(this.prisma, supervisorId);
      await service.recibirTareaFinalizada({ tareaId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /supervisores/:supervisorId/tareas/:tareaId/aprobar
  aprobarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const { tareaId } = TareaIdParam.parse(req.params);
      const service = new SupervisorService(this.prisma, supervisorId);
      await service.aprobarTarea({ tareaId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /supervisores/:supervisorId/tareas/:tareaId/rechazar
  rechazarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const { tareaId } = TareaIdParam.parse(req.params);
      const { observaciones } = RechazarBody.parse(req.body);
      const service = new SupervisorService(this.prisma, supervisorId);
      await service.rechazarTarea({ tareaId, observaciones });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /supervisores/:supervisorId/tareas/pendientes
  listarTareasPendientes: RequestHandler = async (req, res, next) => {
    try {
      const { supervisorId } = SupervisorIdParam.parse(req.params);
      const service = new SupervisorService(this.prisma, supervisorId);
      const list = await service.listarTareasPendientes();
      res.json(list);
    } catch (err) { next(err); }
  };
}
