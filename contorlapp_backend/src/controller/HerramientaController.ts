import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { HerramientaService } from "../services/HerramientaServices";
import {
  CrearHerramientaBody,
  EditarHerramientaBody,
  HerramientaIdParam,
  ListarHerramientasQuery,
} from "../model/Herramienta";

export class HerramientaController {

  // POST /herramientas
  crear: RequestHandler = async (req, res, next) => {
    try {
      const body = CrearHerramientaBody.parse(req.body);
      const service = new HerramientaService(prisma);
      const out = await service.crear(body);
      res.status(201).json(out);
    } catch (err: any) {
      // Unique constraint
      if (err?.code === "P2002") {
        (err as any).status = 409;
        (err as any).message =
          "Ya existe una herramienta con ese nombre/unidad en la empresa.";
      }
      next(err);
    }
  };

  // GET /herramientas?empresaId=&nombre=&take=&skip=
  listar: RequestHandler = async (req, res, next) => {
    try {
      const q = ListarHerramientasQuery.parse(req.query);
      const service = new HerramientaService(prisma);
      const out = await service.listar(q);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /herramientas/:herramientaId
  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const service = new HerramientaService(prisma);
      const out = await service.obtenerPorId(herramientaId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /herramientas/:herramientaId
  editar: RequestHandler = async (req, res, next) => {
    try {
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = EditarHerramientaBody.parse(req.body);

      const service = new HerramientaService(prisma);
      const out = await service.editar(herramientaId, body);
      res.json(out);
    } catch (err: any) {
      if (err?.code === "P2002") {
        (err as any).status = 409;
        (err as any).message =
          "Conflicto: ya existe una herramienta con ese nombre/unidad en la empresa.";
      }
      next(err);
    }
  };

  // DELETE /herramientas/:herramientaId
  eliminar: RequestHandler = async (req, res, next) => {
    try {
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const service = new HerramientaService(prisma);
      await service.eliminar(herramientaId);
      res.status(204).send();
    } catch (err: any) {
      if (err?.code === "P2003") {
        (err as any).status = 409;
        (err as any).message =
          "No se puede eliminar: está relacionada con stock/solicitudes/usos.";
      }
      next(err);
    }
  };
}
