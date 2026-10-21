import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { GerenteService } from "../services/GerenteServices";
import {
  TareaService,
  conSupervisorPorDefecto,
  type ActorConsultaTareas,
} from "../services/TareaServices";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";

const NitParam = z.object({ nit: z.string().trim().min(1) });
const IdParam = z.object({ id: z.coerce.number().int().positive() });

/** Quien consulta o modifica, tal como viene en el token. */
function actorDeTareas(req: Parameters<RequestHandler>[0]): ActorConsultaTareas {
  return {
    id: String(req.user?.sub ?? "").trim(),
    rol: String(req.user?.rol ?? "").trim(),
  };
}

/** Rutas de /tarea-correctiva: correctivas por conjunto (crear, editar, listar). */
export class TareaCorrectivaController {
  // POST /tarea-correctiva/conjuntos/:nit/tareas
  crear: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      // Con actor: el servicio también exige el conjunto en su alcance.
      const actor = (await extraerActorAuditoriaConNombre(req)) ?? { id: null, rol: null };
      const svc = new GerenteService(prisma, empresaId, actor);
      const out = await svc.asignarTarea(
        conSupervisorPorDefecto(actorDeTareas(req), {
          ...(req.body ?? {}),
          conjuntoId: nit,
          tipo: "CORRECTIVA",
        }),
      );
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /tarea-correctiva/tareas/:id (solo dentro del alcance del rol)
  editar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      const actor = (await extraerActorAuditoriaConNombre(req)) ?? { id: null, rol: null };
      const svc = new GerenteService(prisma, empresaId, actor);
      res.json(await svc.editarTarea(id, req.body));
    } catch (err) {
      next(err);
    }
  };

  // GET /tarea-correctiva/conjuntos/:nit/tareas?desde&hasta&tipo
  listarPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = NitParam.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      const tareas = await TareaService.listarTareasDeConjuntoPorRango(
        prisma,
        nit,
        req.query,
        empresaId,
        actorDeTareas(req),
      );
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };
}
