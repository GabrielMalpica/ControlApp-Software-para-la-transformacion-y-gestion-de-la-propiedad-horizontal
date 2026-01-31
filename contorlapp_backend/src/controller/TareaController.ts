import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { TareaService } from "../services/TareaServices";

const IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export class TareaController {

  // POST /tareas  (correctiva por defecto)
  crearTarea: RequestHandler = async (req, res, next) => {
    try {
      const creada = await TareaService.crearTareaCorrectiva(
        prisma,
        req.body
      );
      res.status(201).json(creada);
    } catch (err) {
      next(err);
    }
  };

  // GET /tareas
  listarTareas: RequestHandler = async (req, res, next) => {
    try {
      const list = await TareaService.listarTareas(prisma, req.query);
      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  // GET /tareas/:id
  obtenerTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const tarea = await TareaService.obtenerTarea(prisma, id);
      res.json(tarea);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /tareas/:id
  editarTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const tarea = await TareaService.editarTarea(
        prisma,
        id,
        req.body
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
      await TareaService.eliminarTarea(prisma, id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
