// src/controllers/AdministradorController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { AdministradorService } from "../services/AdministradorServices";

// Validaciones mínimas para params / headers / query
const AdminIdParam = z.object({ adminId: z.coerce.number().int().positive() });
const ConjuntoParam = z.object({ conjuntoId: z.string().min(1) });
const CompromisoParam = z.object({ id: z.coerce.number().int().positive() });
const CrearCompromisoBody = z.object({ titulo: z.string().min(1) });
const ActualizarCompromisoBody = z.object({
  titulo: z.string().min(1).optional(),
  completado: z.boolean().optional(),
});

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

  // GET /administradores/:adminId/conjuntos
  verConjuntos: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(prisma, administradorId);
      const conjuntos = await service.verConjuntos();
      res.json(conjuntos);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/tarea
  solicitarTarea: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(prisma, administradorId);
      const creada = await service.solicitarTarea(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/insumos
  solicitarInsumos: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(prisma, administradorId);
      const creada = await service.solicitarInsumos(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  // POST /administradores/:adminId/solicitudes/maquinaria
  solicitarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const service = new AdministradorService(prisma, administradorId);
      const creada = await service.solicitarMaquinaria(req.body);
      res.status(201).json(creada);
    } catch (err) { next(err); }
  };

  listarCompromisosConjunto: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const { conjuntoId } = ConjuntoParam.parse(req.params);
      const service = new AdministradorService(prisma, administradorId);
      const items = await service.listarCompromisosConjunto(conjuntoId);
      res.json(items);
    } catch (err) { next(err); }
  };

  crearCompromisoConjunto: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const { conjuntoId } = ConjuntoParam.parse(req.params);
      const { titulo } = CrearCompromisoBody.parse(req.body);
      const service = new AdministradorService(prisma, administradorId);
      const creado = await service.crearCompromisoConjunto({
        conjuntoId,
        titulo,
        creadoPorId: req.user?.sub ? String(req.user.sub) : administradorId.toString(),
      });
      res.status(201).json(creado);
    } catch (err) { next(err); }
  };

  actualizarCompromiso: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const { id } = CompromisoParam.parse(req.params);
      const body = ActualizarCompromisoBody.parse(req.body);
      const service = new AdministradorService(prisma, administradorId);
      const updated = await service.actualizarCompromiso(id, body);
      res.json(updated);
    } catch (err) { next(err); }
  };

  eliminarCompromiso: RequestHandler = async (req, res, next) => {
    try {
      const administradorId = resolveAdminId(req);
      const { id } = CompromisoParam.parse(req.params);
      const service = new AdministradorService(prisma, administradorId);
      const out = await service.eliminarCompromiso(id);
      res.json(out);
    } catch (err) { next(err); }
  };
}
