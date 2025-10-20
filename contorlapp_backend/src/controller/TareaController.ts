// src/controllers/TareaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { TareaService } from "../services/TareaServices";
import { InventarioService } from "../services/InventarioServices";

const TareaIdParam = z.object({ tareaId: z.coerce.number().int().positive() });

const EvidenciaBody = z.object({ imagen: z.string().min(1) });

const AprobarBody = z.object({ supervisorId: z.number().int().positive() });

const RechazarBody = z.object({
  supervisorId: z.number().int().positive(),
  observacion: z.string().min(3).max(500),
});

const CompletarBody = z.object({
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.number().int().positive(),
      })
    )
    .default([]),
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

  // POST /tareas/:tareaId/completar
  completarConInsumos: RequestHandler = async (req, res, next) => {
    try {
      const { tareaId } = TareaIdParam.parse(req.params);
      const { insumosUsados } = CompletarBody.parse(req.body);

      // 1) localizar la tarea para conocer su conjunto
      const tarea = await this.prisma.tarea.findUnique({
        where: { id: tareaId },
        select: { conjuntoId: true },
      });
      if (!tarea) { res.status(404).json({ message: "Tarea no encontrada" }); return; }
      if (!tarea.conjuntoId) {
        res.status(400).json({ message: "La tarea no tiene conjunto asignado" });
        return;
      }

      // 2) obtener inventario del conjunto
      const inventario = await this.prisma.inventario.findUnique({
        where: { conjuntoId: tarea.conjuntoId },
        select: { id: true },
      });
      if (!inventario) {
        res.status(400).json({ message: "No existe inventario para el conjunto de la tarea" });
        return;
      }

      // 3) orquestar consumo + cambio de estado usando los services
      const inventarioService = new InventarioService(this.prisma, inventario.id);
      const tareaService = new TareaService(this.prisma, tareaId);

      await tareaService.marcarComoCompletadaConInsumos(
        { insumosUsados },
        {
          consumirInsumoPorId: (payload: unknown) =>
            inventarioService.consumirInsumoPorId(payload),
        }
      );

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
