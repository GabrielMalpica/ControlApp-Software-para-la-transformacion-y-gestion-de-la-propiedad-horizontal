// src/controllers/UbicacionController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { UbicacionService } from "../services/UbicacionServices";

const UbicacionIdParam = z.object({ ubicacionId: z.coerce.number().int().positive() });
const ElementoBody = z.object({ nombre: z.string().min(1) });
const BuscarQuery = z.object({ nombre: z.string().min(1) });

export class UbicacionController {

  // POST /ubicaciones/:ubicacionId/elementos
  agregarElemento: RequestHandler = async (req, res, next) => {
    try {
      const { ubicacionId } = UbicacionIdParam.parse(req.params);
      const body = ElementoBody.parse(req.body);
      const service = new UbicacionService(prisma, ubicacionId);
      await service.agregarElemento(body);
      res.status(201).json({ message: "Elemento creado" });
    } catch (err) { next(err); }
  };

  // GET /ubicaciones/:ubicacionId/elementos
  listarElementos: RequestHandler = async (_req, res, next) => {
    try {
      const { ubicacionId } = UbicacionIdParam.parse(_req.params);
      const service = new UbicacionService(prisma, ubicacionId);
      const list = await service.listarElementos();
      res.json(list);
    } catch (err) { next(err); }
  };

  // GET /ubicaciones/:ubicacionId/elementos/buscar?nombre=...
  buscarElementoPorNombre: RequestHandler = async (req, res, next) => {
    try {
      const { ubicacionId } = UbicacionIdParam.parse(req.params);
      const { nombre } = BuscarQuery.parse(req.query);
      const service = new UbicacionService(prisma, ubicacionId);
      const item = await service.buscarElementoPorNombre({ nombre });
      if (!item) { res.status(404).json({ message: "Elemento no encontrado" }); return; }
      res.json(item);
    } catch (err) { next(err); }
  };
}
