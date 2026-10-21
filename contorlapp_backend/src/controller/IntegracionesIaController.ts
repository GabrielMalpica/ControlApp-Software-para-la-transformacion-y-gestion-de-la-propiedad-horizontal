// src/controller/IntegracionesIaController.ts
import type { Request, RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { IntegracionesIaService, type ActorPanel } from "../services/IntegracionesIaService";
import { resolverNombreUsuario } from "../utils/auditoria";

const service = new IntegracionesIaService(prisma);

const IdParam = z.object({ id: z.string().uuid() });
const DecisionBody = z.object({ decision: z.enum(["aprobar", "rechazar"]) });
const PermisosBody = z.object({ permisos: z.array(z.string().min(1).max(40)).min(1).max(30) });
const ActividadQuery = z.object({ limite: z.coerce.number().int().min(1).max(200).optional() });

async function actor(req: Request): Promise<ActorPanel> {
  const id = String(req.user?.sub ?? "");
  return { id, nombre: await resolverNombreUsuario(id), empresaId: await empresaIdAutenticada(req) };
}

export class IntegracionesIaController {
  configuracion: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.configuracion(await actor(req)));
    } catch (err) {
      next(err);
    }
  };

  listar: RequestHandler = async (req, res, next) => {
    try {
      res.json({ conexiones: await service.listar(await actor(req)) });
    } catch (err) {
      next(err);
    }
  };

  revocar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      res.json(await service.revocar(await actor(req), id));
    } catch (err) {
      next(err);
    }
  };

  revocarTodas: RequestHandler = async (req, res, next) => {
    try {
      res.json(await service.revocarTodasLasMias(await actor(req)));
    } catch (err) {
      next(err);
    }
  };

  reducirPermisos: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const { permisos } = PermisosBody.parse(req.body);
      res.json(await service.reducirPermisos(await actor(req), id, permisos));
    } catch (err) {
      next(err);
    }
  };

  actividad: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const { limite } = ActividadQuery.parse(req.query);
      res.json({ actividad: await service.actividad(await actor(req), id, limite) });
    } catch (err) {
      next(err);
    }
  };

  aprobaciones: RequestHandler = async (req, res, next) => {
    try {
      res.json({ aprobaciones: await service.aprobacionesPendientes(await actor(req)) });
    } catch (err) {
      next(err);
    }
  };

  decidir: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const { decision } = DecisionBody.parse(req.body);
      res.json(await service.decidir(await actor(req), id, decision));
    } catch (err) {
      next(err);
    }
  };
}
