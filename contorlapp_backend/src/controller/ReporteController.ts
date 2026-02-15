// src/controllers/ReporteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { ReporteService } from "../services/ReporteService";
import { EstadoTarea } from "../generated/prisma";

const service = new ReporteService(prisma);

// ✅ Base
const RangoQueryBase = z.object({
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
});

// ✅ Rango solo
const RangoQuery = RangoQueryBase.refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

// ✅ Rango + conjunto opcional (dashboard general o filtrado)
const RangoConConjuntoOpcionalQuery = RangoQueryBase.merge(
  z.object({ conjuntoId: z.string().min(1).optional() }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

// ✅ Insumos requiere conjunto
const UsoInsumosQuery = RangoQueryBase.merge(
  z.object({ conjuntoId: z.string().min(1) }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

// ✅ Tareas por estado (requiere conjunto + estado)
const EstadoQuery = RangoQueryBase.merge(
  z.object({
    conjuntoId: z.string().min(1),
    estado: z.nativeEnum(EstadoTarea),
  }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const ZonificacionPreventivasQuery = RangoQueryBase.merge(
  z.object({
    conjuntoId: z.string().min(1).optional(),
    soloActivas: z.enum(["true", "false", "1", "0"]).optional(),
  }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

export class ReporteController {
  // =========================
  // DASHBOARD (NUEVOS)
  // =========================

  // GET /reporte/kpis?desde=&hasta=&conjuntoId?
  kpis: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.kpis(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/serie-diaria?desde=&hasta=&conjuntoId?
  serieDiariaPorEstado: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.serieDiariaPorEstado(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/por-conjunto?desde=&hasta=
  resumenPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoQuery.parse(req.query);
      const out = await service.resumenPorConjunto(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/por-operario?desde=&hasta=&conjuntoId?
  resumenPorOperario: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.resumenPorOperario(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/duracion-promedio?desde=&hasta=&conjuntoId?
  duracionPromedioPorEstado: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.duracionPromedioPorEstado(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/mensual-detalle?desde=&hasta=&conjuntoId?
  // (dataset para PDF)
  reporteMensualDetalle: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.reporteMensualDetalle(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/zonificacion/preventivas?desde=&hasta=&conjuntoId?&soloActivas=true|false
  zonificacionPreventivas: RequestHandler = async (req, res, next) => {
    try {
      const raw = ZonificacionPreventivasQuery.parse(req.query);
      const q = {
        ...raw,
        soloActivas:
          raw.soloActivas == null
            ? undefined
            : raw.soloActivas === "true" || raw.soloActivas === "1",
      };
      const out = await service.zonificacionPreventivas(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // =========================
  // LO QUE YA TENÍAS
  // =========================

  // GET /reporte/tareas/aprobadas?desde=&hasta=
  tareasAprobadasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoQuery.parse(req.query);
      const out = await service.tareasAprobadasPorFecha(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/rechazadas?desde=&hasta=
  tareasRechazadasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoQuery.parse(req.query);
      const out = await service.tareasRechazadasPorFecha(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/insumos/uso?conjuntoId=&desde=&hasta=
  usoDeInsumosPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const q = UsoInsumosQuery.parse(req.query);
      const out = await service.usoDeInsumosPorFecha(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/estado?conjuntoId=&estado=&desde=&hasta=
  tareasPorEstado: RequestHandler = async (req, res, next) => {
    try {
      const q = EstadoQuery.parse(req.query);
      const out = await service.tareasPorEstado(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/detalle?conjuntoId=&estado=&desde=&hasta=
  tareasConDetalle: RequestHandler = async (req, res, next) => {
    try {
      const q = EstadoQuery.parse(req.query);
      const out = await service.tareasConDetalle(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/maquinaria/top?desde=&hasta=&conjuntoId?
  usoMaquinariaTop: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.usoMaquinariaTop(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/herramientas/top?desde=&hasta=&conjuntoId?
  usoHerramientaTop: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.usoHerramientaTop(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tipos?desde=&hasta=&conjuntoId?
  conteoPorTipo: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.conteoPorTipo(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
