// src/controllers/CronogramaHerramientaController.ts
import { RequestHandler } from "express";

import { prisma } from "../db/prisma";
import { CronogramaHerramientaService } from "../services/CronogramaHerramientaService";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";

export class CronogramaHerramientaController {
  // GET /empresas/:empresaNit/necesidades?anio=&mes=&herramientaId=&conjuntoId=&soloPendientes=
  listarNecesidades: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaHerramientaService(
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
  asignarHerramienta: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaHerramientaService(
        prisma,
        req.params.empresaNit,
        await extraerActorAuditoriaConNombre(req),
      );
      const out = await service.asignarHerramienta(req.body);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /empresas/:empresaNit/asignaciones/:usoId
  liberarAsignacion: RequestHandler = async (req, res, next) => {
    try {
      const service = new CronogramaHerramientaService(
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
