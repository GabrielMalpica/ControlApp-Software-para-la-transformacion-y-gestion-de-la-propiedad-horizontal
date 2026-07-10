import { RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { PlanEsperanzaService } from "../services/PlanEsperanzaService";

const service = new PlanEsperanzaService(prisma);

const NitParam = z.object({ nit: z.string().min(1) });
const PlanIdParam = z.object({ id: z.coerce.number().int().positive() });
const DiagnosticoIdParam = z.object({
  id: z.coerce.number().int().positive(),
});

export class PlanEsperanzaController {
  getConfig: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const config = await service.obtenerConfig(nit);
      res.json(config);
    } catch (err) {
      next(err);
    }
  };

  updateConfig: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const { intervaloMeses } = z
        .object({ intervaloMeses: z.number().int().min(1).max(60) })
        .parse(req.body);
      const config = await service.actualizarConfig(nit, intervaloMeses);
      res.json(config);
    } catch (err) {
      next(err);
    }
  };

  iniciarPlan: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const { mantenerEvidencias, planAnteriorId } = z
        .object({
          mantenerEvidencias: z.boolean().optional().default(false),
          planAnteriorId: z.number().int().positive().optional(),
        })
        .parse(req.body);
      const plan = await service.iniciarPlan(
        nit,
        mantenerEvidencias,
        planAnteriorId
      );
      res.status(201).json(plan);
    } catch (err) {
      next(err);
    }
  };

  getPlanActivo: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const plan = await service.obtenerPlanActivo(nit);
      res.json(plan);
    } catch (err) {
      next(err);
    }
  };

  listarPlanes: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const planes = await service.listarPlanes(nit);
      res.json(planes);
    } catch (err) {
      next(err);
    }
  };

  guardarDiagnostico: RequestHandler = async (req, res, next) => {
    try {
      const { id } = DiagnosticoIdParam.parse(req.params);
      const body = z
        .object({
          valoracion: z.coerce.number().min(0).max(5).optional().nullable(),
          observaciones: z.string().optional().nullable(),
        })
        .parse(req.body);

      const file = req.file;
      let conjuntoNombre: string | undefined;

      if (file) {
        const diagnostico = await service.obtenerDiagnostico(id);
        if (!diagnostico) {
          res.status(404).json({ error: "Diagnostico no encontrado" });
          return;
        }
        const conjunto = await prisma.conjunto.findUnique({
          where: { nit: diagnostico.conjuntoId },
          select: { nombre: true },
        });
        conjuntoNombre = conjunto?.nombre ?? "Conjunto";

        const result = await service.guardarDiagnostico(id, {
          valoracion: body.valoracion,
          observaciones: body.observaciones,
          filePath: file.path,
          fileName: `area_${diagnostico.elementoId}_${Date.now()}${file.originalname ? file.originalname.substring(file.originalname.lastIndexOf(".")) : ".jpg"}`,
          mimeType: file.mimetype,
          conjuntoNombre,
        });
        res.json(result);
      } else {
        const result = await service.guardarDiagnostico(id, {
          valoracion: body.valoracion,
          observaciones: body.observaciones,
        });
        res.json(result);
      }
    } catch (err) {
      next(err);
    }
  };

  finalizarPlan: RequestHandler = async (req, res, next) => {
    try {
      const { id } = PlanIdParam.parse(req.params);
      const plan = await service.finalizarPlan(id);
      res.json(plan);
    } catch (err) {
      next(err);
    }
  };

  obtenerInforme: RequestHandler = async (req, res, next) => {
    try {
      const { id } = PlanIdParam.parse(req.params);
      const informe = await service.obtenerInforme(id);
      if (!informe) {
        res.status(404).json({ error: "Plan no encontrado" });
        return;
      }
      res.json(informe);
    } catch (err) {
      next(err);
    }
  };

  obtenerHistorico: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const historico = await service.obtenerHistorico(nit);
      res.json(historico);
    } catch (err) {
      next(err);
    }
  };

  reiniciarPlan: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const { mantenerEvidencias } = z
        .object({
          mantenerEvidencias: z.boolean().optional().default(false),
        })
        .parse(req.body);
      const plan = await service.reiniciarPlan(nit, mantenerEvidencias);
      res.json(plan);
    } catch (err) {
      next(err);
    }
  };

  verificarZonasNuevas: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const resultado = await service.verificarZonasNuevas(nit);
      res.json(resultado);
    } catch (err) {
      next(err);
    }
  };

  obtenerLineaTiempoElemento: RequestHandler = async (req, res, next) => {
    try {
      const { elementoId } = z
        .object({ elementoId: z.coerce.number().int().positive() })
        .parse(req.params);
      const entries = await service.obtenerLineaTiempoElemento(elementoId);
      res.json(entries);
    } catch (err) {
      next(err);
    }
  };
}
