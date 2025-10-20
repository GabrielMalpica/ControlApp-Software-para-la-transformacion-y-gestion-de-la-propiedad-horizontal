// src/controllers/OperarioController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { OperarioService } from "../services/OperarioServices";
import { InventarioService } from "../services/InventarioServices";

// ── Schemas ─────────────────────────────────────────────────────────────────
const OperarioIdParam = z.object({ operarioId: z.coerce.number().int().positive() });
const TareaIdParam   = z.object({ tareaId: z.coerce.number().int().positive() });

// Query/body helpers
const FechaQuery = z.object({ fecha: z.coerce.date() });

const AsignarBody = z.object({
  tareaId: z.number().int().positive(),
});

const CompletarBody = z.object({
  tareaId: z.number().int().positive(),
  evidencias: z.array(z.string()).optional().default([]),
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.number().int().positive(),
      })
    )
    .optional()
    .default([]),
});

export class OperarioController {
  private prisma: PrismaClient;

  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /operarios/:operarioId/tareas/asignar
  asignarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { tareaId }   = AsignarBody.parse(req.body);

      const service = new OperarioService(this.prisma, operarioId);
      await service.asignarTarea({ tareaId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /operarios/:operarioId/tareas/:tareaId/iniciar
  iniciarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { tareaId }    = TareaIdParam.parse(req.params);

      const service = new OperarioService(this.prisma, operarioId);
      await service.iniciarTarea({ tareaId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /operarios/:operarioId/tareas/completar
  marcarComoCompletada: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const body = CompletarBody.parse(req.body);

      // 1) Resolver inventario del conjunto de la tarea
      const tarea = await this.prisma.tarea.findUnique({
        where: { id: body.tareaId },
        select: { conjuntoId: true },
      });
      if (!tarea?.conjuntoId) {
        const e: any = new Error("La tarea no existe o no tiene conjunto asignado.");
        e.status = 400; throw e;
      }
      const inventario = await this.prisma.inventario.findUnique({
        where: { conjuntoId: tarea.conjuntoId },
        select: { id: true },
      });
      if (!inventario) {
        const e: any = new Error("No existe inventario para el conjunto de la tarea.");
        e.status = 400; throw e;
      }

      // 2) Ejecutar flujo de cierre con consumo de insumos
      const service = new OperarioService(this.prisma, operarioId);
      const inventarioService = new InventarioService(this.prisma, inventario.id);
      await service.marcarComoCompletada(body, inventarioService);

      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /operarios/:operarioId/tareas/:tareaId/no-completada
  marcarComoNoCompletada: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { tareaId }    = TareaIdParam.parse(req.params);

      const service = new OperarioService(this.prisma, operarioId);
      await service.marcarComoNoCompletada({ tareaId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /operarios/:operarioId/tareas/dia?fecha=YYYY-MM-DD
  tareasDelDia: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { fecha }      = FechaQuery.parse(req.query);

      const service = new OperarioService(this.prisma, operarioId);
      const tareas = await service.tareasDelDia({ fecha });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /operarios/:operarioId/tareas
  listarTareas: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const service = new OperarioService(this.prisma, operarioId);
      const list = await service.listarTareas();
      res.json(list);
    } catch (err) { next(err); }
  };

  // GET /operarios/:operarioId/horas/restantes?fecha=YYYY-MM-DD
  horasRestantesEnSemana: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { fecha }      = FechaQuery.parse(req.query);

      const service = new OperarioService(this.prisma, operarioId);
      const horas = await service.horasRestantesEnSemana({ fecha });
      res.json({ horasRestantes: horas });
    } catch (err) { next(err); }
  };

  // GET /operarios/:operarioId/horas/resumen?fecha=YYYY-MM-DD
  resumenDeHoras: RequestHandler = async (req, res, next) => {
    try {
      const { operarioId } = OperarioIdParam.parse(req.params);
      const { fecha }      = FechaQuery.parse(req.query);

      const service = new OperarioService(this.prisma, operarioId);
      const resumen = await service.resumenDeHoras({ fecha });
      res.json({ resumen });
    } catch (err) { next(err); }
  };
}
