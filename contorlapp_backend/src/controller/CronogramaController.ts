// src/controllers/CronogramaController.ts
import { RequestHandler, Request } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { AuditoriaService } from "../services/AuditoriaService";
import { CronogramaService } from "../services/CronogramaServices"; // <- singular
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";

// Schemas para params/query
const NitSchema = z.object({ nit: z.string().min(3) });
const OperarioIdSchema = z.object({
  operarioId: z.coerce.number().int().positive(),
});
const FechaSchema = z.object({ fecha: z.coerce.date() });
const RangoSchema = z
  .object({
    inicio: z.coerce.date(),
    fin: z.coerce.date(),
  })
  .refine((d) => d.fin >= d.inicio, {
    message: "fin debe ser mayor o igual a inicio",
    path: ["fin"],
  });
const UbicacionSchema = z.object({ ubicacion: z.string().min(1) });

const FiltroBodySchema = z
  .object({
    operarioId: z.number().int().positive().optional(),
    fechaExacta: z.coerce.date().optional(),
    fechaInicio: z.coerce.date().optional(),
    fechaFin: z.coerce.date().optional(),
    ubicacion: z.string().optional(),
  })
  .refine(
    (d) => {
      if (d.fechaExacta) return true;
      return (
        (!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin))
      );
    },
    { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." }
  );

// Resolver NIT (conjuntoId)
function resolveConjuntoId(req: Request): string {
  const paramsNit = req.params?.nit as string | undefined;
  const parsed = NitSchema.safeParse({ nit: paramsNit });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el NIT del conjunto.");
    e.status = 400;
    throw e;
  }
  return parsed.data.nit;
}

export class CronogramaController {

  // GET /conjuntos/:nit/operarios/sugerir?inicio=...&fin=...&max=5&requiereFuncion=...
  sugerirOperarios: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const inicio = new Date(String(req.query.inicio ?? ""));
      const fin = new Date(String(req.query.fin ?? ""));
      const max = req.query.max ? Number(req.query.max) : undefined;
      const requiereFuncion = req.query.requiereFuncion as string | undefined;

      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.sugerirOperarios({
        fechaInicio: inicio,
        fechaFin: fin,
        max,
        requiereFuncion,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma?anio=2025&mes=11&borrador=true|false
  cronogramaMensual: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const borrador =
        req.query.borrador === undefined
          ? false
          : String(req.query.borrador) === "true";
      const service = new CronogramaService(prisma, conjuntoId);
      const list = await service.cronogramaMensual({ anio, mes, borrador });
      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  informeMensualActividad: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const borrador =
        req.query.borrador === undefined
          ? false
          : String(req.query.borrador) === "true";
      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.informeMensualActividad({ anio, mes, borrador });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  informeActividadJerarquico: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const borrador =
        req.query.borrador === undefined
          ? false
          : String(req.query.borrador) === "true";
      const operarioId = req.query.operarioId
        ? String(req.query.operarioId)
        : undefined;
      const semanaInicio = req.query.semanaInicio
        ? String(req.query.semanaInicio)
        : undefined;
      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.informeActividadJerarquico({
        anio,
        mes,
        borrador,
        operarioId,
        semanaInicio,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarExcluidasStandby: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const fecha = req.query.fecha ? new Date(String(req.query.fecha)) : undefined;
      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.listarExcluidasStandby({ anio, mes, fecha });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  programarExcluidaComoCorrectiva: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const actor = await extraerActorAuditoriaConNombre(req);
      const service = new CronogramaService(prisma, conjuntoId, actor);
      const out = await service.programarExcluidaComoCorrectiva({
        ...req.body,
        // El id de la URL manda sobre el del body.
        excluidaId: Number(req.params.id),
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/excluidas-standby/:id/opciones-reemplazo?fecha=...
  opcionesReemplazoExcluida: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.listarOpcionesReemplazoExcluida({
        excluidaId: req.params.id,
        fecha: req.query.fecha,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/cronograma/excluidas-standby/:id/reasignar-operario
  reasignarOperarioExcluidaStandby: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const actor = await extraerActorAuditoriaConNombre(req);
      const service = new CronogramaService(prisma, conjuntoId, actor);
      const out = await service.reasignarOperarioExcluidaPublicada({
        ...req.body,
        excluidaId: Number(req.params.id),
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/informe-excluidas?anio=&mes=
  informeExcluidas: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.informeExcluidasDelPeriodo({
        anio: req.query.anio,
        mes: req.query.mes,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/auditoria?modulo=&entidad=&entidadId=&anio=&mes=&accion=&limit=
  listarAuditoria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new AuditoriaService(prisma);
      const out = await service.listar(conjuntoId, req.query);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/auditoria/trazabilidad  { entidad, entidadIds[] }
  trazabilidadAuditoria: RequestHandler = async (req, res, next) => {
    try {
      resolveConjuntoId(req);
      const service = new AuditoriaService(prisma);
      const out = await service.trazabilidadPorEntidad(req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/informe-auditoria?anio=&mes=&modulo=
  informeAuditoria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new AuditoriaService(prisma);
      const out = await service.informePeriodo(conjuntoId, req.query);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  eliminarCronogramaPublicado: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const actor = await extraerActorAuditoriaConNombre(req);
      const service = new CronogramaService(prisma, conjuntoId, actor);
      const out = await service.eliminarCronogramaPublicado({
        anio: req.query.anio ?? req.body?.anio,
        mes: req.query.mes ?? req.body?.mes,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/mes?anio=2025&mes=10&operarioId=&tipo=&borrador=
  calendarioMensual: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const operarioId = req.query.operarioId
        ? Number(req.query.operarioId)
        : undefined;
      const tipo = req.query.tipo as
        | "PREVENTIVA"
        | "CORRECTIVA"
        | "TODAS"
        | undefined;
      const borrador =
        req.query.borrador == null
          ? false
          : String(req.query.borrador) === "true";

      if (
        !Number.isFinite(anio) ||
        !Number.isFinite(mes) ||
        mes < 1 ||
        mes > 12
      ) {
        res.status(400).json({ error: "anio/mes inválidos" });
        return; // <- clave: no retornes el Response
      }

      const service = new CronogramaService(prisma, conjuntoId);
      const out = await service.calendarioMensual({
        anio,
        mes,
        operarioId,
        tipo,
        borrador,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/tareas/por-operario/:operarioId
  tareasPorOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { operarioId } = OperarioIdSchema.parse(req.params);
      const service = new CronogramaService(prisma, conjuntoId);
      const tareas = await service.tareasPorOperario({ operarioId });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/tareas/por-fecha?fecha=YYYY-MM-DD
  tareasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { fecha } = FechaSchema.parse({ fecha: req.query.fecha ?? "" });
      const service = new CronogramaService(prisma, conjuntoId);
      const tareas = await service.tareasPorFecha({ fecha });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/tareas/en-rango?inicio=YYYY-MM-DD&fin=YYYY-MM-DD
  tareasEnRango: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { inicio, fin } = RangoSchema.parse({
        inicio: req.query.inicio ?? "",
        fin: req.query.fin ?? "",
      });
      const service = new CronogramaService(prisma, conjuntoId);
      const tareas = await service.tareasEnRango({
        fechaInicio: inicio,
        fechaFin: fin,
      });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/tareas/por-ubicacion?ubicacion=...
  tareasPorUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { ubicacion } = UbicacionSchema.parse({
        ubicacion: req.query.ubicacion,
      });
      const service = new CronogramaService(prisma, conjuntoId);
      const tareas = await service.tareasPorUbicacion({ ubicacion });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/cronograma/tareas/filtrar
  tareasPorFiltro: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const filtro = FiltroBodySchema.parse(req.body);
      const service = new CronogramaService(prisma, conjuntoId);
      const tareas = await service.tareasPorFiltro(filtro);
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/eventos
  exportarComoEventosCalendario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new CronogramaService(prisma, conjuntoId);
      const eventos = await service.exportarComoEventosCalendario();
      res.json(eventos);
    } catch (err) {
      next(err);
    }
  };
}
