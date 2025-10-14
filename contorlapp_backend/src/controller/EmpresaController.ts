// src/controllers/EmpresaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { EmpresaService } from "../services/EmpresaServices";

const IdParamSchema = z.object({ id: z.coerce.number().int().positive() });
const NitHeaderSchema = z.object({ nit: z.string().min(3) });

function resolveEmpresaId(req: any): string {
  const headersNit = (req.header("x-empresa-id") ?? req.header("x-nit"))?.trim();
  const queryNit = typeof req.query.nit === "string" ? req.query.nit : undefined;
  const paramsNit = req.params?.nit as string | undefined;

  const nit = headersNit || queryNit || paramsNit;
  if (!nit) {
    // lanza con status para que tu error middleware lo tome
    const e: any = new Error("Falta el NIT de la empresa.");
    e.status = 400;
    throw e;
  }
  return NitHeaderSchema.parse({ nit }).nit;
}

export class EmpresaController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  crearEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const service = new EmpresaService(this.prisma, "901191875-4");
      const creada = await service.crearEmpresa(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  agregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const creada = await service.agregarMaquinaria(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  listarMaquinariaDisponible: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const items = await service.listarMaquinariaDisponible();
      res.json(items);
    } catch (err) { next(err); }
  };

  obtenerMaquinariaPrestada: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const items = await service.obtenerMaquinariaPrestada();
      res.json(items);
    } catch (err) { next(err); }
  };

  agregarJefeOperaciones: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const jefe = await service.agregarJefeOperaciones(req.body);
      res.status(201).json(jefe);
    } catch (err) { next(err); }
  };

  recibirSolicitudTarea: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(this.prisma, empresaId);
      const upd = await service.recibirSolicitudTarea({ id });
      res.json(upd);
    } catch (err) { next(err); }
  };

  eliminarSolicitudTarea: RequestHandler = async (req, res, next) => {
    try {
      resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(this.prisma, "");
      await service.eliminarSolicitudTarea({ id });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  solicitudesTareaPendientes: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const list = await service.solicitudesTareaPendientes();
      res.json(list);
    } catch (err) { next(err); }
  };

  agregarInsumoAlCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const insumo = await service.agregarInsumoAlCatalogo(req.body);
      res.status(201).json(insumo);
    } catch (err) { next(err); }
  };

  listarCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(this.prisma, empresaId);
      const items = await service.listarCatalogo();
      res.json(items);
    } catch (err) { next(err); }
  };

  buscarInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(this.prisma, empresaId);
      const item = await service.buscarInsumoPorId({ id });
      if (!item) {
        res.status(404).json({ message: "Insumo no encontrado" });
        return;
      }
      res.json(item);
    } catch (err) { next(err); }
  };
}
