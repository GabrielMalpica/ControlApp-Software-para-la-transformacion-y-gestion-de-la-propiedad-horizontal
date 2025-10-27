// src/controllers/SolicitudMaquinariaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { SolicitudMaquinariaService } from "../services/SolicitudMaquinariaServices";

const IdParam = z.object({ id: z.coerce.number().int().positive() });

const FiltroQuery = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  maquinariaId: z.coerce.number().int().optional(),
  operarioId: z.coerce.number().int().optional(),
  aprobado: z.coerce.boolean().optional(),
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});

export class SolicitudMaquinariaController {
  private prisma: PrismaClient;
  private service: SolicitudMaquinariaService;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
    this.service = new SolicitudMaquinariaService(this.prisma);
  }

  crear: RequestHandler = async (req, res, next) => {
    try {
      const out = await this.service.crear(req.body);
      res.status(201).json(out);
    } catch (err) { next(err); }
  };

  editar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await this.service.editar(id, req.body);
      res.json(out);
    } catch (err) { next(err); }
  };

  aprobar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await this.service.aprobar(id, req.body);
      res.json(out);
    } catch (err) { next(err); }
  };

  listar: RequestHandler = async (req, res, next) => {
    try {
      const f = FiltroQuery.parse(req.query);
      const out = await this.service.listar(f);
      res.json(out);
    } catch (err) { next(err); }
  };

  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      const out = await this.service.obtener(id);
      if (!out) { res.status(404).json({ message: "No encontrado" }); return; }
      res.json(out);
    } catch (err) { next(err); }
  };

  eliminar: RequestHandler = async (req, res, next) => {
    try {
      const { id } = IdParam.parse(req.params);
      await this.service.eliminar(id);
      res.status(204).send();
    } catch (err) { next(err); }
  };
}
