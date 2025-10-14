// src/controllers/AdministradorController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { AdministradorService } from "../services/AdministradorServices";

// Validaciones mínimas para params / headers / query
const AdminIdParam = z.object({ adminId: z.coerce.number().int().positive() });

// Puedes aceptar adminId también por header o query si te conviene multi-uso
function resolveAdminId(req: any): number {
  const paramId = req.params?.adminId;
  const headerId = req.header("x-admin-id");
  const queryId = typeof req.query.adminId === "string" ? req.query.adminId : undefined;

  const parsed = AdminIdParam.safeParse({ adminId: paramId ?? headerId ?? queryId });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el administradorId.");
    e.status = 400;
    throw e;
  }
  return parsed.data.adminId;
}

export class AdministradorController {
  private prisma: PrismaClient;

  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // GET /administradores/:adminId/conjuntos
  verConjuntos: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(this.prisma, administradorId);
      const conjuntos = await service.verConjuntos();
      res.json(conjuntos);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/tarea
  solicitarTarea: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(this.prisma, administradorId);
      const creada = await service.solicitarTarea(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/insumos
  solicitarInsumos: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(this.prisma, administradorId);
      const creada = await service.solicitarInsumos(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/maquinaria
  solicitarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(this.prisma, administradorId);
      const creada = await service.solicitarMaquinaria(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };
}
