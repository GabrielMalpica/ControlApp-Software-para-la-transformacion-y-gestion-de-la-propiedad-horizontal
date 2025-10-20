// src/controllers/CronogramaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { CronogramaService } from "../services/CronogramaServices";

// Schemas para params/query
const NitSchema = z.object({ nit: z.string().min(3) });
const OperarioIdSchema = z.object({ operarioId: z.coerce.number().int().positive() });
const FechaSchema = z.object({ fecha: z.coerce.date() });
const RangoSchema = z.object({
  inicio: z.coerce.date(),
  fin: z.coerce.date(),
}).refine((d) => d.fin >= d.inicio, {
  message: "fin debe ser mayor o igual a inicio",
  path: ["fin"],
});
const UbicacionSchema = z.object({ ubicacion: z.string().min(1) });

// Body para filtro avanzado (empareja tu TareasPorFiltroDTO)
const FiltroBodySchema = z.object({
  operarioId: z.number().int().positive().optional(),
  fechaExacta: z.coerce.date().optional(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  ubicacion: z.string().optional(),
}).refine((d) => {
  if (d.fechaExacta) return true;
  return (!d.fechaInicio && !d.fechaFin) || (Boolean(d.fechaInicio) && Boolean(d.fechaFin));
}, { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." });

// Resolver NIT (conjuntoId)
function resolveConjuntoId(req: any): string {
  const headerNit = (req.header("x-conjunto-id") ?? req.header("x-nit"))?.trim();
  const queryNit = typeof req.query.nit === "string" ? req.query.nit : undefined;
  const paramsNit = req.params?.nit as string | undefined;
  const nit = headerNit || queryNit || paramsNit;
  const parsed = NitSchema.safeParse({ nit });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el NIT del conjunto.");
    e.status = 400;
    throw e;
  }
  return parsed.data.nit;
}

export class CronogramaController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // GET /conjuntos/:nit/cronograma/tareas/por-operario/:operarioId
  tareasPorOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { operarioId } = OperarioIdSchema.parse(req.params);
      const service = new CronogramaService(this.prisma, conjuntoId);
      const tareas = await service.tareasPorOperario({ operarioId });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/cronograma/tareas/por-fecha?fecha=YYYY-MM-DD
  tareasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { fecha } = FechaSchema.parse({ fecha: req.query.fecha ?? "" });
      const service = new CronogramaService(this.prisma, conjuntoId);
      const tareas = await service.tareasPorFecha({ fecha });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/cronograma/tareas/en-rango?inicio=YYYY-MM-DD&fin=YYYY-MM-DD
  tareasEnRango: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { inicio, fin } = RangoSchema.parse({ inicio: req.query.inicio ?? "", fin: req.query.fin ?? ""});
      const service = new CronogramaService(this.prisma, conjuntoId);
      const tareas = await service.tareasEnRango({ fechaInicio: inicio, fechaFin: fin });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/cronograma/tareas/por-ubicacion?ubicacion=...
  tareasPorUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { ubicacion } = UbicacionSchema.parse({ ubicacion: req.query.ubicacion });
      const service = new CronogramaService(this.prisma, conjuntoId);
      const tareas = await service.tareasPorUbicacion({ ubicacion });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // POST /conjuntos/:nit/cronograma/tareas/filtrar
  tareasPorFiltro: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const filtro = FiltroBodySchema.parse(req.body);
      const service = new CronogramaService(this.prisma, conjuntoId);
      const tareas = await service.tareasPorFiltro(filtro);
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/cronograma/eventos
  exportarComoEventosCalendario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new CronogramaService(this.prisma, conjuntoId);
      const eventos = await service.exportarComoEventosCalendario();
      res.json(eventos);
    } catch (err) { next(err); }
  };
}
