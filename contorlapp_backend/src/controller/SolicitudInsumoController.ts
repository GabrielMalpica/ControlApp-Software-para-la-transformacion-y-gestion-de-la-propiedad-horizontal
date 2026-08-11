// src/controllers/SolicitudInsumoController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { SolicitudInsumoService } from "../services/SolicitudInsumoServices";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";

const IdParam = z.object({ id: z.coerce.number().int().positive() });

const FiltroQuery = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  aprobado: z.coerce.boolean().optional(),
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});

// aprobar puede venir vacío
const AprobarBody = z.object({
  fechaAprobacion: z.coerce.date().optional(),
  empresaId: z.string().min(3).optional(),
});

const service = new SolicitudInsumoService(prisma);

export class SolicitudInsumoController {

  crear: RequestHandler = async (req, res, next) => {
    try {
      const actorId = req.user?.sub ? String(req.user.sub) : null;
      const empresaId = await empresaIdAutenticada(req);
      const out = await service.crear({ ...req.body, empresaId }, actorId);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  aprobar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const body = AprobarBody.parse(req.body ?? {});
      const empresaId = await empresaIdAutenticada(req);
      const out = await service.aprobar(id, { ...body, empresaId });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listar: RequestHandler = async (req, res, next) => {
    try {
      const f = FiltroQuery.parse(req.query);
      const empresaId = await empresaIdAutenticada(req);
      const out = await service.listar({ ...f, empresaId });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await service.obtener(id);
      if (!out) {
        res.status(404).json({ message: "No encontrado" });
        return;
      }
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  eliminar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      await service.eliminar(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
