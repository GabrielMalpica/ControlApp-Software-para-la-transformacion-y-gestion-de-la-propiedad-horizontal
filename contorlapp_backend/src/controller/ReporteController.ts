// src/controllers/ReporteController.ts
import { Request, RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { ReporteService } from "../services/ReporteService";
import { EstadoTarea } from "@prisma/client";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import fs from "fs";
import { claveDia } from "../services/InformeMensualModelo";
import { informeMensualJobs, type JobInforme } from "../services/InformeMensualJobs";
import { crearEjecutorInforme } from "../services/InformeMensualService";

async function serviceFor(req: Request) {
  return new ReporteService(prisma, await empresaIdAutenticada(req));
}

function logPerf(nombre: string, inicio: number, detalle?: string) {
  const duracionSeg = ((Date.now() - inicio) / 1000).toFixed(2);
  console.log(
    `[perf] ${nombre}${detalle ? ` ${detalle}` : ""}: ${duracionSeg} s`,
  );
}

function detalleConjunto(conjuntoId?: string) {
  return conjuntoId?.trim() || "general";
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

// ✅ Informe mensual en PDF (se genera en segundo plano)
const MAX_DIAS_INFORME = 366;
const InformeMensualPdfBody = z
  .object({
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
    conjuntoId: z.string().trim().min(1).optional(),
  })
  .refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
  })
  .refine(
    (d) => d.hasta.getTime() - d.desde.getTime() <= MAX_DIAS_INFORME * 86_400_000,
    { path: ["hasta"], message: "El rango del informe no puede superar un año" },
  );

const InformeMensualPdfParams = z.object({ jobId: z.string().uuid() });

function estadoJobInforme(job: JobInforme) {
  return {
    jobId: job.id,
    estado: job.estado,
    progreso: job.progreso,
    mensaje: job.mensaje,
    error: job.error,
    posicionCola: informeMensualJobs.posicionEnCola(job.id),
    nombreArchivo: job.estado === "LISTO" ? job.nombreArchivo : null,
  };
}

function usuarioIdDe(req: Request): string {
  const id = String(req.user?.sub ?? "").trim();
  if (!id) {
    throw Object.assign(new Error("No autenticado"), { status: 401 });
  }
  return id;
}

export class ReporteController {
  // =========================
  // DASHBOARD (NUEVOS)
  // =========================

  // GET /reporte/kpis?desde=&hasta=&conjuntoId?
  kpis: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await (await serviceFor(req)).kpis(q);
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
      const out = await (await serviceFor(req)).serieDiariaPorEstado(q);
      logPerf("Reporte serie diaria", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/compromisos?desde=&hasta=&conjuntoId?
  compromisosDashboard: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await (await serviceFor(req)).compromisosDashboard(q);
      logPerf("Reporte compromisos", inicio, await detalleConjunto(q.conjuntoId));
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
      const out = await (await serviceFor(req)).resumenPorConjunto(q);
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
      const out = await (await serviceFor(req)).resumenPorOperario(q);
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
      const out = await (await serviceFor(req)).duracionPromedioPorEstado(q);
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
      const out = await (await serviceFor(req)).reporteMensualDetalle(q);
      logPerf("Reporte mensual detalle", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // POST /reporte/informe-mensual/pdf  { desde, hasta, conjuntoId? }
  // Responde 202 al instante; el PDF se arma en segundo plano.
  iniciarInformeMensualPdf: RequestHandler = async (req, res, next) => {
    try {
      const body = InformeMensualPdfBody.parse(req.body);
      const usuarioId = usuarioIdDe(req);
      const empresaId = await empresaIdAutenticada(req);

      if (body.conjuntoId) {
        const conjunto = await prisma.conjunto.findFirst({
          where: { nit: body.conjuntoId, empresaId },
          select: { nit: true },
        });
        if (!conjunto) {
          throw Object.assign(new Error("Conjunto no encontrado"), { status: 404 });
        }
      }

      const clave = [
        empresaId,
        body.conjuntoId ?? "*",
        claveDia(body.desde),
        claveDia(body.hasta),
      ].join("|");
      const job = informeMensualJobs.iniciar({
        usuarioId,
        clave,
        ejecutar: crearEjecutorInforme({
          prisma,
          empresaId,
          conjuntoId: body.conjuntoId,
          desde: body.desde,
          hasta: body.hasta,
        }),
      });
      res.status(202).json(estadoJobInforme(job));
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/informe-mensual/pdf/:jobId
  estadoInformeMensualPdf: RequestHandler = async (req, res, next) => {
    try {
      const { jobId } = InformeMensualPdfParams.parse(req.params);
      const job = informeMensualJobs.obtener(jobId, usuarioIdDe(req));
      if (!job) {
        throw Object.assign(
          new Error("El informe ya no está disponible. Genéralo de nuevo."),
          { status: 404 },
        );
      }
      res.json(estadoJobInforme(job));
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/informe-mensual/pdf/:jobId/archivo
  descargarInformeMensualPdf: RequestHandler = async (req, res, next) => {
    try {
      const { jobId } = InformeMensualPdfParams.parse(req.params);
      const job = informeMensualJobs.obtener(jobId, usuarioIdDe(req));
      if (!job) {
        throw Object.assign(
          new Error("El informe ya no está disponible. Genéralo de nuevo."),
          { status: 404 },
        );
      }
      if (job.estado !== "LISTO") {
        throw Object.assign(new Error("El informe todavía no está listo."), {
          status: 409,
        });
      }
      const { size } = await fs.promises.stat(job.archivo);
      res.setHeader("Content-Type", "application/pdf");
      res.setHeader("Content-Length", String(size));
      res.setHeader(
        "Content-Disposition",
        `attachment; filename="${job.nombreArchivo.replace(/[^A-Za-z0-9._-]/g, "_")}"`,
      );
      res.setHeader("Cache-Control", "private, no-store");
      const stream = fs.createReadStream(job.archivo);
      stream.on("error", (e) => {
        console.error("[informe-mensual] error leyendo el PDF:", e);
        if (!res.headersSent) {
          res.status(404).json({ message: "El informe ya no está disponible." });
        } else {
          res.destroy();
        }
      });
      stream.pipe(res);
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
      const out = await (await serviceFor(req)).zonificacionPreventivas(q);
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
      const out = await (await serviceFor(req)).tareasAprobadasPorFecha(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/tareas/rechazadas?desde=&hasta=
  tareasRechazadasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const q = RangoQuery.parse(req.query);
      const out = await (await serviceFor(req)).tareasRechazadasPorFecha(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /reporte/insumos/uso?conjuntoId=&desde=&hasta= (conjuntoId opcional:
  // sin el, agrega el uso de insumos de toda la empresa en una sola consulta).
  usoDeInsumosPorFecha: RequestHandler = async (req, res, next) => {
    const inicio = Date.now();
    try {
      const q = RangoConConjuntoOpcionalQuery.parse(req.query);
      const out = await (await serviceFor(req)).usoDeInsumosPorFecha(q);
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
      const out = await (await serviceFor(req)).tareasPorEstado(q);
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
      const out = await (await serviceFor(req)).tareasConDetalle(q);
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
      const out = await (await serviceFor(req)).usoMaquinariaTop(q);
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
      const out = await (await serviceFor(req)).usoHerramientaTop(q);
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
      const out = await (await serviceFor(req)).conteoPorTipo(q);
      logPerf("Reporte tipos", inicio, await detalleConjunto(q.conjuntoId));
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
