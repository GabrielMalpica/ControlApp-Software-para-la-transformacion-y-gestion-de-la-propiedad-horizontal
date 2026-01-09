import { RequestHandler } from "express";
import { PrismaClient } from "../generated/prisma";
import { z } from "zod";
import { TareaService } from "../services/TareaServices";

const IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

export class TareaController {
  private prisma: PrismaClient;

  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /tareas  (correctiva por defecto)
  crearTarea: RequestHandler = async (req, res, next) => {
    try {
      const creada = await TareaService.crearTareaCorrectiva(
        this.prisma,
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
      const list = await TareaService.listarTareas(this.prisma, req.query);
      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  // GET /tareas/:id
  obtenerTarea: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParamSchema.parse(req.params);
      const tarea = await TareaService.obtenerTarea(this.prisma, id);
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
        this.prisma,
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
      await TareaService.eliminarTarea(this.prisma, id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
