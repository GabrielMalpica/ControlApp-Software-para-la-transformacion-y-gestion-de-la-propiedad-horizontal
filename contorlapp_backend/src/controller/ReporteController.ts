// src/controllers/ReporteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { ReporteService } from "../services/ReporteService";
import { EstadoTarea } from "../generated/prisma";

const RangoQuery = z.object({
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
}).refine(d => d.hasta >= d.desde, { path: ["hasta"], message: "hasta debe ser >= desde" });

const UsoInsumosQuery = z.object({
  conjuntoId: z.string().min(1),
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
}).refine(d => d.hasta >= d.desde, { path: ["hasta"], message: "hasta debe ser >= desde" });

const EstadoQuery = z.object({
  conjuntoId: z.string().min(1),
  estado: z.nativeEnum(EstadoTarea),
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
}).refine(d => d.hasta >= d.desde, { path: ["hasta"], message: "hasta debe ser >= desde" });

const service = new ReporteService(prisma);

export class ReporteController {

  // GET /reportes/tareas/aprobadas?desde=&hasta=
  tareasAprobadasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const { desde, hasta } = RangoQuery.parse(req.query);
      const out = await service.tareasAprobadasPorFecha({ desde, hasta });
      res.json(out);
    } catch (err) { next(err); }
  };

  // GET /reportes/tareas/rechazadas?desde=&hasta=
  tareasRechazadasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const { desde, hasta } = RangoQuery.parse(req.query);
      const out = await service.tareasRechazadasPorFecha({ desde, hasta });
      res.json(out);
    } catch (err) { next(err); }
  };

  // GET /reportes/insumos/uso?conjuntoId=&desde=&hasta=
  usoDeInsumosPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId, desde, hasta } = UsoInsumosQuery.parse(req.query);
      const out = await service.usoDeInsumosPorFecha({ conjuntoId, desde, hasta });
      res.json(out);
    } catch (err) { next(err); }
  };

  // GET /reportes/tareas/estado?conjuntoId=&estado=&desde=&hasta=
  tareasPorEstado: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId, estado, desde, hasta } = EstadoQuery.parse(req.query);
      const out = await service.tareasPorEstado({ conjuntoId, estado, desde, hasta });
      res.json(out);
    } catch (err) { next(err); }
  };

  // GET /reportes/tareas/detalle?conjuntoId=&estado=&desde=&hasta=
  tareasConDetalle: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId, estado, desde, hasta } = EstadoQuery.parse(req.query);
      const out = await service.tareasConDetalle({ conjuntoId, estado, desde, hasta });
      res.json(out);
    } catch (err) { next(err); }
  };
}
