// src/controllers/ReporteController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { ReporteService } from "../services/ReporteService";
import { EstadoTarea } from "@prisma/client";

const service = new ReporteService(prisma);

function logPerf(nombre: string, inicio: number, detalle?: string) {
  const duracionSeg = ((Date.now() - inicio) / 1000).toFixed(2);
  console.log(
    `[perf] ${nombre}${detalle ? ` ${detalle}` : ""}: ${duracionSeg} s`,
  );
}

async function detalleConjunto(conjuntoId?: string) {
  if (!conjuntoId) {
    return "general";
  }

  const conjunto = await prisma.conjunto.findUnique({
    where: { nit: conjuntoId },
    select: { nombre: true },
  });

  const nombre = (conjunto?.nombre ?? "").trim();
  return nombre.length > 0 ? `${nombre} (${conjuntoId})` : conjuntoId;
}

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
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.kpis(q);
      logPerf("Reporte KPIs", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/serie-diaria?desde=&hasta=&conjuntoId?
  serieDiariaPorEstado: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.serieDiariaPorEstado(q);
      logPerf("Reporte serie diaria", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/por-conjunto?desde=&hasta=
  resumenPorConjunto: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoQuery.parse(req.query);
      const out = await service.resumenPorConjunto(q);
      logPerf("Reporte por conjunto", inicio, "general");
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/por-operario?desde=&hasta=&conjuntoId?
  resumenPorOperario: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.resumenPorOperario(q);
      logPerf("Reporte por operario", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/duracion-promedio?desde=&hasta=&conjuntoId?
  duracionPromedioPorEstado: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.duracionPromedioPorEstado(q);
      logPerf(
        "Reporte duracion promedio",
        inicio,
        await detalleConjunto(q.conjuntoId),
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/mensual-detalle?desde=&hasta=&conjuntoId?
  // (dataset para PDF)
  reporteMensualDetalle: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.reporteMensualDetalle(q);
      logPerf("Reporte mensual detalle", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/zonificacion/preventivas?desde=&hasta=&conjuntoId?&soloActivas=true|false
  zonificacionPreventivas: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
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
      logPerf(
        "Reporte zonificacion preventivas",
        inicio,
        await detalleConjunto(q.conjuntoId),
      );
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
    const inicio = Date.now();
    try {
      const q = UsoInsumosQuery.parse(req.query);
      const out = await service.usoDeInsumosPorFecha(q);
      logPerf("Reporte insumos", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/estado?conjuntoId=&estado=&desde=&hasta=
  tareasPorEstado: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = EstadoQuery.parse(req.query);
      const out = await service.tareasPorEstado(q);
      logPerf(
        `Reporte tareas estado ${q.estado}`,
        inicio,
        await detalleConjunto(q.conjuntoId),
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/detalle?conjuntoId=&estado=&desde=&hasta=
  tareasConDetalle: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = EstadoQuery.parse(req.query);
      const out = await service.tareasConDetalle(q);
      logPerf(
        `Reporte tareas detalle ${q.estado}`,
        inicio,
        await detalleConjunto(q.conjuntoId),
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/maquinaria/top?desde=&hasta=&conjuntoId?
  usoMaquinariaTop: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.usoMaquinariaTop(q);
      logPerf("Reporte top maquinaria", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/herramientas/top?desde=&hasta=&conjuntoId?
  usoHerramientaTop: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.usoHerramientaTop(q);
      logPerf(
        "Reporte top herramientas",
        inicio,
        await detalleConjunto(q.conjuntoId),
      );
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tipos?desde=&hasta=&conjuntoId?
  conteoPorTipo: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await service.conteoPorTipo(q);
      logPerf("Reporte tipos", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
