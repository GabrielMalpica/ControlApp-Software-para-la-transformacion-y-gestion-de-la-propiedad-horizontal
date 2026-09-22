import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { TareaService } from "../services/TareaServices";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";

const IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

async function actorAutenticado(req: any): Promise<{ id: string; rol: string; nombre?: string | null }> {
  const id = String(req.user?.sub ?? "").trim();
  const rol = String(req.user?.rol ?? "").trim();
  const usuario = await prisma.usuario.findUnique({
    where: { id },
    select: { nombre: true },
  });
  return { id, rol, nombre: usuario?.nombre ?? null };
}

export class TareaController {

  // POST /tareas  (correctiva por defecto)
  crearTarea: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const creada = await TareaService.crearTareaCorrectiva(
        prisma,
        req.body,
        empresaId,
      );
      res.status(201).json(creada);
    } catch (err) {
      next(err);
    }
  };

  // GET /tareas
  listarTareas: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const list = await TareaService.listarTareas(prisma, req.query, empresaId);
      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  // GET /tareas/:id
  obtenerTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      const tarea = await TareaService.obtenerTarea(prisma, id, empresaId);
      res.json(tarea);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /tareas/:id
  editarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      const tarea = await TareaService.editarTarea(
        prisma,
        id,
        req.body,
        empresaId,
      );
      res.json(tarea);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /tareas/:id
  eliminarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      await TareaService.eliminarTarea(prisma, id, empresaId);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /tareas/:id/corregir-cierre (multipart)
  corregirCierre: RequestHandler = async (req: any, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const empresaId = await empresaIdAutenticada(req);
      const actor = await actorAutenticado(req);
      const files = (req.files ?? []) as Express.Multer.File[];

      const tarea = await TareaService.corregirCierre(
        prisma,
        id,
        req.body,
        files,
        empresaId,
        actor,
      );
      res.json(tarea);
    } catch (err) {
      next(err);
    }
  };
}
