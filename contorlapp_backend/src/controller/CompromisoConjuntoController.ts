import fs from "fs";
import { RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { CompromisoConjuntoService } from "../services/CompromisoConjuntoService";
import { ESTADOS_PQRS } from "../services/CompromisoConjuntoService";

const service = new CompromisoConjuntoService(prisma);

const ConjuntoParam = z.object({ conjuntoId: z.string().min(1) });
const CompromisoParam = z.object({ id: z.coerce.number().int().positive() });
const CrearBody = z.object({ titulo: z.string().min(1) });
const ActualizarBody = z.object({
  titulo: z.string().min(1).optional(),
});
const SeguimientoBody = z.object({
  estado: z.enum(ESTADOS_PQRS),
  observacion: z.string().max(2000).optional(),
});

export class CompromisoConjuntoController {
  listarGlobal: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const items = await service.listarGlobal(empresaId);
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  listarPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoParam.parse(req.params);
      const items = await service.listarPorConjunto(conjuntoId);
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  crear: RequestHandler = async (req, res, next) => {
    try {
      const { conjuntoId } = ConjuntoParam.parse(req.params);
      const { titulo } = CrearBody.parse(req.body);
      const creado = await service.crear({
        conjuntoId,
        titulo,
        creadoPorId: req.user?.sub ? String(req.user.sub) : null,
      });
      res.status(201).json(creado);
    } catch (err) {
      next(err);
    }
  };

  actualizar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = CompromisoParam.parse(req.params);
      const body = ActualizarBody.parse(req.body);
      const updated = await service.actualizar(id, body);
      res.json(updated);
    } catch (err) {
      next(err);
    }
  };

  agregarSeguimiento: RequestHandler = async (req, res, next) => {
    const files = (req.files as Express.Multer.File[]) ?? [];
    try {
      const { id } = CompromisoParam.parse(req.params);
      const { estado, observacion } = SeguimientoBody.parse(req.body);
      const actualizado = await service.agregarSeguimiento({
        id,
        estado,
        observacion,
        actorId: String(req.user?.sub ?? ""),
        files,
        evidenciasCaptura: req.body?.evidenciasCaptura,
      });
      res.json(actualizado);
    } catch (err) {
      await Promise.all(files.map((file) => fs.promises.unlink(file.path).catch(() => undefined)));
      next(err);
    }
  };

  eliminar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = CompromisoParam.parse(req.params);
      const out = await service.eliminar(id);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
