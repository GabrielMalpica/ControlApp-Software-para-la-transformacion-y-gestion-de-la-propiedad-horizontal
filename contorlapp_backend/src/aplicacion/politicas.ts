// src/aplicacion/politicas.ts
//
// Reglas de autorizacion invocables fuera de Express. Son las mismas que
// aplican los middlewares de la API (`requirePermission`,
// `requireConjuntoScope`, `requireResourceScope`): permiso efectivo del rol
// en la empresa, y todo recurso dentro de la empresa y del alcance del actor.
import type { PrismaClient } from "@prisma/client";

import { PermissionService } from "../services/PermissionService";
import { alcanceConjuntos, conjuntoEnAlcance, type AlcanceConjuntos } from "./alcanceConjuntos";
import { errorAplicacion, noEncontrado, type ContextoAccion } from "./contexto";

export async function asegurarPermiso(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  ...permisos: string[]
): Promise<void> {
  const servicio = new PermissionService(prisma);
  const efectivos = await servicio.getEffectivePermissionsForRole(ctx.empresaId, ctx.actor.rol);
  if (!PermissionService.hasAnyPermission(efectivos, permisos)) {
    throw errorAplicacion(403, "No autorizado para esta accion segun los permisos del rol.", "DENEGADO");
  }
}

export function alcanceDe(prisma: PrismaClient, ctx: ContextoAccion): Promise<AlcanceConjuntos> {
  return alcanceConjuntos(prisma, {
    usuarioId: ctx.actor.id,
    rol: ctx.actor.rol,
    empresaId: ctx.empresaId,
  });
}

/** Conjunto de la empresa y en el alcance del actor, o 404. */
export async function conjuntoAccesible(
  prisma: PrismaClient,
  ctx: ContextoAccion,
  nit: string,
): Promise<{ nit: string; nombre: string; activo: boolean }> {
  const conjunto = await prisma.conjunto.findFirst({
    where: { nit, empresaId: ctx.empresaId },
    select: { nit: true, nombre: true, activo: true },
  });
  if (!conjunto) throw noEncontrado("Conjunto no encontrado.");
  if (!conjuntoEnAlcance(await alcanceDe(prisma, ctx), conjunto.nit)) {
    throw noEncontrado("Conjunto no encontrado.");
  }
  return conjunto;
}

/** Operario de la empresa (con su nombre y conjuntos), o 404. */
export async function operarioDeEmpresa(prisma: PrismaClient, ctx: ContextoAccion, id: string) {
  const operario = await prisma.operario.findFirst({
    where: { id, empresaId: ctx.empresaId },
    select: {
      id: true,
      funciones: true,
      usuario: { select: { nombre: true, activo: true } },
      conjuntos: { select: { nit: true, nombre: true }, orderBy: { nombre: "asc" } },
    },
  });
  if (!operario) throw noEncontrado("Operario no encontrado.");
  return operario;
}
