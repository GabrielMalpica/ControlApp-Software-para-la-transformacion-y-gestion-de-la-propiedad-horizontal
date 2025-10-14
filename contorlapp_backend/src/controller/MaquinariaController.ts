// src/controllers/MaquinariaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { MaquinariaService } from "../services/MaquinariaServices";

// Params y body mínimos
const MaquinariaIdParam = z.object({ maquinariaId: z.coerce.number().int().positive() });
const AsignarBody = z.object({
  conjuntoId: z.string().min(3),
  responsableId: z.number().int().positive().optional(),
  diasPrestamo: z.number().int().positive().optional(),
});

export class MaquinariaController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /maquinarias/:maquinariaId/asignar
  asignarAConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const body = AsignarBody.parse(req.body);
      const service = new MaquinariaService(this.prisma, maquinariaId);
      const updated = await service.asignarAConjunto(body);
      res.status(201).json(updated);
    } catch (err) { next(err); }
  };

  // POST /maquinarias/:maquinariaId/devolver
  devolver: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const service = new MaquinariaService(this.prisma, maquinariaId);
      const updated = await service.devolver();
      res.status(200).json(updated);
    } catch (err) { next(err); }
  };

  // GET /maquinarias/:maquinariaId/disponible
  estaDisponible: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const service = new MaquinariaService(this.prisma, maquinariaId);
      const disponible = await service.estaDisponible();
      res.json({ disponible });
    } catch (err) { next(err); }
  };

  // GET /maquinarias/:maquinariaId/responsable
  obtenerResponsable: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const service = new MaquinariaService(this.prisma, maquinariaId);
      const responsable = await service.obtenerResponsable();
      res.json({ responsable });
    } catch (err) { next(err); }
  };

  // GET /maquinarias/:maquinariaId/resumen
  resumenEstado: RequestHandler = async (req, res, next) => {
    try {
      const { maquinariaId } = MaquinariaIdParam.parse(req.params);
      const service = new MaquinariaService(this.prisma, maquinariaId);
      const resumen = await service.resumenEstado();
      res.json({ resumen });
    } catch (err) { next(err); }
  };
}
