// src/controllers/CronogramaMaquinariaController.ts
import { RequestHandler } from "express";

import { prisma } from "../db/prisma";
import { CronogramaMaquinariaService } from "../services/CronogramaMaquinariaService";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";

export class CronogramaMaquinariaController {
  // GET /empresas/:empresaNit/necesidades?anio=&mes=&tipo=&conjuntoId=&soloPendientes=
  listarNecesidades: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaMaquinariaService(
        prisma,
        req.params.empresaNit,
      );
      const out = await service.listarNecesidades(req.query);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // POST /empresas/:empresaNit/asignaciones
  asignarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaMaquinariaService(
        prisma,
        req.params.empresaNit,
        await extraerActorAuditoriaConNombre(req),
      );
      const out = await service.asignarMaquinaria(req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /empresas/:empresaNit/asignaciones/:usoId
  liberarAsignacion: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaMaquinariaService(
        prisma,
        req.params.empresaNit,
        await extraerActorAuditoriaConNombre(req),
      );
      const out = await service.liberarAsignacion({ usoId: req.params.usoId });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
