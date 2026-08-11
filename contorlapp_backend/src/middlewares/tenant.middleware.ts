import { Request, RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { PermissionService } from "../services/PermissionService";

const permissionService = new PermissionService(prisma);

type ScopedResource =
  | "administrador"
  | "compromiso"
  | "diagnostico"
  | "elemento"
  | "herramienta"
  | "inventario"
  | "insumo"
  | "maquinaria"
  | "operario"
  | "plan"
  | "residente"
  | "solicitudHerramienta"
  | "solicitudInsumo"
  | "solicitudMaquinaria"
  | "solicitudTarea"
  | "supervisor"
  | "tarea"
  | "ubicacion"
  | "usoMaquinaria"
  | "usuario";

type HttpError = Error & { status: number };

function httpError(status: number, message: string): HttpError {
  const error = new Error(message) as HttpError;
  error.status = status;
  return error;
}

export async function empresaIdAutenticada(req: Request): Promise<string> {
  const userId = String(req.user?.sub ?? "").trim();
  const role = String(req.user?.rol ?? "").trim();
  if (!userId || !role) throw httpError(401, "No autenticado");

  const claimEmpresaId = String(req.user?.empresaId ?? "").trim();
  const roleEmpresaId = await permissionService.resolveEmpresaIdForUser(userId, role);

  if (claimEmpresaId && claimEmpresaId !== roleEmpresaId) {
    throw httpError(401, "El contexto de empresa del token ya no es valido");
  }

  req.user!.empresaId = roleEmpresaId;
  return roleEmpresaId;
}

function param(req: Request, paramName: string): string {
  const value = String(req.params[paramName] ?? "").trim();
  if (!value) throw httpError(400, `Falta el parametro ${paramName}`);
  return value;
}

export function requireEmpresaScope(paramName: string): RequestHandler {
  return async (req, _res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      if (param(req, paramName) !== empresaId) {
        throw httpError(404, "Recurso no encontrado");
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireConjuntoScope(paramName: string): RequestHandler {
  return async (req, _res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const conjuntoId = param(req, paramName);
      const conjunto = await prisma.conjunto.findFirst({
        where: { nit: conjuntoId, empresaId },
        select: { nit: true },
      });
      if (!conjunto) throw httpError(404, "Recurso no encontrado");
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireBodyConjuntoScope(fieldName = "conjuntoId"): RequestHandler {
  return async (req, _res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const conjuntoId = String(req.body?.[fieldName] ?? "").trim();
      if (!conjuntoId) throw httpError(400, `Falta el campo ${fieldName}`);
      const conjunto = await prisma.conjunto.findFirst({
        where: { nit: conjuntoId, empresaId },
        select: { nit: true },
      });
      if (!conjunto) throw httpError(404, "Recurso no encontrado");
      next();
    } catch (error) {
      next(error);
    }
  };
}

export function requireSelfScope(paramName: string): RequestHandler {
  return (req, _res, next) => {
    try {
      if (param(req, paramName) !== String(req.user?.sub ?? "").trim()) {
        throw httpError(403, "No autorizado para operar sobre otro usuario");
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}

async function resourceBelongsToEmpresa(
  resource: ScopedResource,
  rawId: string,
  empresaId: string,
): Promise<boolean> {
  const id = Number(rawId);
  const numericId = Number.isInteger(id) && id > 0 ? id : -1;

  switch (resource) {
    case "administrador":
      return Boolean(
        await prisma.administrador.findFirst({
          where: { id: rawId, conjuntos: { some: { empresaId } } },
          select: { id: true },
        }),
      );
    case "compromiso":
      return Boolean(
        await prisma.compromisoConjunto.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "operario":
      return Boolean(
        await prisma.operario.findFirst({ where: { id: rawId, empresaId }, select: { id: true } }),
      );
    case "supervisor":
      return Boolean(
        await prisma.supervisor.findFirst({ where: { id: rawId, empresaId }, select: { id: true } }),
      );
    case "maquinaria":
      return Boolean(
        await prisma.maquinaria.findFirst({
          where: {
            id: numericId,
            OR: [{ empresaId }, { conjuntoPropietario: { empresaId } }],
          },
          select: { id: true },
        }),
      );
    case "tarea":
      return Boolean(
        await prisma.tarea.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "inventario":
      return Boolean(
        await prisma.inventario.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "insumo":
      return Boolean(
        await prisma.insumo.findFirst({
          where: { id: numericId, empresaId },
          select: { id: true },
        }),
      );
    case "solicitudTarea":
      return Boolean(
        await prisma.solicitudTarea.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "solicitudInsumo":
      return Boolean(
        await prisma.solicitudInsumo.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "solicitudMaquinaria":
      return Boolean(
        await prisma.solicitudMaquinaria.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "solicitudHerramienta":
      return Boolean(
        await prisma.solicitudHerramienta.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "ubicacion":
      return Boolean(
        await prisma.ubicacion.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "usoMaquinaria":
      return Boolean(
        await prisma.usoMaquinaria.findFirst({
          where: { id: numericId, tarea: { conjunto: { empresaId } } },
          select: { id: true },
        }),
      );
    case "elemento":
      return Boolean(
        await prisma.elemento.findFirst({
          where: { id: numericId, ubicacion: { conjunto: { empresaId } } },
          select: { id: true },
        }),
      );
    case "plan":
      return Boolean(
        await prisma.planEsperanza.findFirst({
          where: { id: numericId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "residente":
      return Boolean(
        await prisma.residente.findFirst({
          where: { id: rawId, conjunto: { empresaId } },
          select: { id: true },
        }),
      );
    case "diagnostico":
      return Boolean(
        await prisma.diagnosticoArea.findFirst({
          where: { id: numericId, planEsperanza: { conjunto: { empresaId } } },
          select: { id: true },
        }),
      );
    case "herramienta":
      return Boolean(
        await prisma.herramienta.findFirst({ where: { id: numericId, empresaId }, select: { id: true } }),
      );
    case "usuario":
      return Boolean(
        await prisma.usuario.findFirst({
          where: {
            id: rawId,
            OR: [
              { gerente: { empresaId } },
              { jefeOperaciones: { empresaId } },
              { supervisor: { empresaId } },
              { operario: { empresaId } },
              { administrador: { conjuntos: { some: { empresaId } } } },
              { residente: { conjunto: { empresaId } } },
            ],
          },
          select: { id: true },
        }),
      );
  }
}

export function requireResourceScope(
  resource: ScopedResource,
  paramName: string,
): RequestHandler {
  return async (req, _res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const rawId = param(req, paramName);
      if (!(await resourceBelongsToEmpresa(resource, rawId, empresaId))) {
        throw httpError(404, "Recurso no encontrado");
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}
