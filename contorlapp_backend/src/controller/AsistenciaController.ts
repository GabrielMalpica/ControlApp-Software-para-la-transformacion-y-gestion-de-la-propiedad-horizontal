import { RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { AsistenciaService } from "../services/AsistenciaService";
import { AsistenciaExcelService } from "../services/AsistenciaExcelService";

const service = new AsistenciaService(prisma);
const excelService = new AsistenciaExcelService(prisma);

const ConjuntoParam = z.object({ nit: z.string().min(1) });
const ConceptoParam = z.object({ id: z.coerce.number().int().positive() });
const TurnoParam = z.object({ id: z.coerce.number().int().positive() });

const PeriodoQuery = z.object({
  conjuntoId: z.string().min(1).optional(),
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
});

const ActualizarConceptoBody = z.object({
  nombre: z.string().min(1).optional(),
  colorHex: z.string().min(3).optional(),
  cuentaComoTrabajado: z.boolean().optional(),
  activo: z.boolean().optional(),
});

const CheckinBody = z.object({
  conjuntoId: z.string().min(1),
  qrPayload: z.string().min(1),
  latitud: z.coerce.number().min(-90).max(90).optional().nullable(),
  longitud: z.coerce.number().min(-180).max(180).optional().nullable(),
});

const UpsertRegistroBody = z.object({
  operarioId: z.string().min(1),
  fecha: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  conceptoId: z.coerce.number().int().positive(),
  conjuntoId: z.string().min(1).optional().nullable(),
  observacion: z.string().max(500).optional().nullable(),
});

const BulkUpsertRegistroBody = z.object({
  operarioIds: z.array(z.string().min(1)).min(1),
  fechaInicio: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  fechaFin: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  conceptoId: z.coerce.number().int().positive(),
  conjuntoId: z.string().min(1).optional().nullable(),
  observacion: z.string().max(500).optional().nullable(),
});

const TurnosExtraQuery = z.object({
  conjuntoId: z.string().min(1).optional(),
  operarioId: z.string().min(1).optional(),
  anio: z.coerce.number().int().min(2000).max(2100).optional(),
  mes: z.coerce.number().int().min(1).max(12).optional(),
});

const CrearTurnoExtraBody = z.object({
  operarioId: z.string().min(1),
  conjuntoId: z.string().min(1).optional().nullable(),
  fecha: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  tipo: z.enum(["TURNO", "NOVENA", "OTRO"]).default("TURNO"),
  esReemplazo: z.boolean().default(false),
  operarioReemplazadoId: z.string().min(1).optional().nullable(),
  reemplazadoNombreLibre: z.string().max(200).optional().nullable(),
  motivo: z.string().max(300).optional().nullable(),
  valorNegociado: z.coerce.number().nonnegative().optional().nullable(),
  turnosOrdinarios: z.coerce.number().int().min(0).max(31).optional(),
  turnosDominicales: z.coerce.number().int().min(0).max(31).optional(),
});

const ActualizarTurnoExtraBody = z.object({
  motivo: z.string().max(300).optional().nullable(),
  valorNegociado: z.coerce.number().nonnegative().optional().nullable(),
  turnosOrdinarios: z.coerce.number().int().min(0).max(31).optional(),
  turnosDominicales: z.coerce.number().int().min(0).max(31).optional(),
  estado: z.enum(["PENDIENTE", "PAGADO", "CANCELADO"]).optional(),
});

export class AsistenciaController {
  listarConceptos: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const items = await service.listarConceptos(empresaId);
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  actualizarConcepto: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = ConceptoParam.parse(req.params);
      const body = ActualizarConceptoBody.parse(req.body);
      const updated = await service.actualizarConcepto(empresaId, id, body);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  };

  obtenerQr: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoParam.parse(req.params);
      const qr = await service.obtenerQr(nit);
      res.json(qr);
    } catch (err) {
      next(err);
    }
  };

  regenerarQr: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoParam.parse(req.params);
      const qr = await service.regenerarQr(nit, {
        id: req.user?.sub ?? null,
        rol: req.user?.rol ?? null,
      });
      res.json(qr);
    } catch (err) {
      next(err);
    }
  };

  checkin: RequestHandler = async (req, res, next) => {
    try {
      const body = CheckinBody.parse(req.body);
      const operarioId = String(req.user?.sub ?? "").trim();
      if (!operarioId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const resultado = await service.checkin({
        operarioId,
        conjuntoId: body.conjuntoId,
        qrPayload: body.qrPayload,
        latitud: body.latitud ?? null,
        longitud: body.longitud ?? null,
      });
      res.json(resultado);
    } catch (err) {
      next(err);
    }
  };

  getGrid: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const query = PeriodoQuery.parse(req.query);
      const grid = await service.getGrid({
        empresaId,
        conjuntoId: query.conjuntoId ?? null,
        anio: query.anio,
        mes: query.mes,
      });
      res.json(grid);
    } catch (err) {
      next(err);
    }
  };

  getResumen: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const query = PeriodoQuery.parse(req.query);
      const resumen = await service.getResumen({
        empresaId,
        conjuntoId: query.conjuntoId ?? null,
        anio: query.anio,
        mes: query.mes,
      });
      res.json(resumen);
    } catch (err) {
      next(err);
    }
  };

  exportarExcel: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const query = PeriodoQuery.parse(req.query);
      const buffer = await excelService.exportar({
        empresaId,
        conjuntoId: query.conjuntoId ?? null,
        anio: query.anio,
        mes: query.mes,
      });

      const nombreArchivo = `asistencia_${query.anio}_${String(query.mes).padStart(2, "0")}.xlsx`;
      res.setHeader(
        "Content-Type",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
      );
      res.setHeader("Content-Disposition", `attachment; filename="${nombreArchivo}"`);
      res.status(200).send(buffer);
    } catch (err) {
      next(err);
    }
  };

  upsertRegistro: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const body = UpsertRegistroBody.parse(req.body);
      const registro = await service.upsertRegistro({
        empresaId,
        operarioId: body.operarioId,
        fecha: body.fecha,
        conceptoId: body.conceptoId,
        conjuntoId: body.conjuntoId,
        observacion: body.observacion,
        actorId: req.user?.sub ?? null,
      });
      res.json(registro);
    } catch (err) {
      next(err);
    }
  };

  bulkUpsertRegistro: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const body = BulkUpsertRegistroBody.parse(req.body);
      const resultado = await service.bulkUpsertRegistro({
        empresaId,
        operarioIds: body.operarioIds,
        fechaInicio: body.fechaInicio,
        fechaFin: body.fechaFin,
        conceptoId: body.conceptoId,
        conjuntoId: body.conjuntoId,
        observacion: body.observacion,
        actorId: req.user?.sub ?? null,
      });
      res.json(resultado);
    } catch (err) {
      next(err);
    }
  };

  listarTurnosExtra: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const query = TurnosExtraQuery.parse(req.query);
      const items = await service.listarTurnosExtra({ empresaId, ...query });
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  crearTurnoExtra: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const body = CrearTurnoExtraBody.parse(req.body);
      const creado = await service.crearTurnoExtra({
        empresaId,
        ...body,
        registradoPorId: req.user?.sub ?? null,
      });
      res.status(201).json(creado);
    } catch (err) {
      next(err);
    }
  };

  actualizarTurnoExtra: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = TurnoParam.parse(req.params);
      const body = ActualizarTurnoExtraBody.parse(req.body);
      const updated = await service.actualizarTurnoExtra(empresaId, id, body);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  };

  eliminarTurnoExtra: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = TurnoParam.parse(req.params);
      const out = await service.eliminarTurnoExtra(empresaId, id);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
