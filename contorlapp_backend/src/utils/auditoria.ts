// src/utils/auditoria.ts
import type { Request } from "express";

import { prisma } from "../db/prisma";
import type { ActorAuditoria } from "../model/Auditoria";

/** Cache de nombres por id de usuario: el actor se repite en cada peticion de una misma sesion. */
const nombresPorUsuario = new Map<string, string | null>();

/**
 * Actor sincrono a partir del JWT (`req.user` que deja `authRequired`).
 * No resuelve el nombre: usa `extraerActorAuditoriaConNombre` cuando el nombre importe.
 */
export function extraerActorAuditoria(req: Request): ActorAuditoria | undefined {
  const user = req.user;
  if (!user?.sub) return undefined;

  return {
    id: String(user.sub),
    rol: user.rol ?? null,
    nombre: nombresPorUsuario.get(String(user.sub)) ?? null,
  };
}

/** Igual que `extraerActorAuditoria`, pero resolviendo el nombre del usuario (cacheado). */
export async function extraerActorAuditoriaConNombre(
  req: Request,
): Promise<ActorAuditoria | undefined> {
  const actor = extraerActorAuditoria(req);
  if (!actor?.id) return actor;
  if (actor.nombre) return actor;

  return { ...actor, nombre: await resolverNombreUsuario(actor.id) };
}

export async function resolverNombreUsuario(usuarioId: string): Promise<string | null> {
  if (nombresPorUsuario.has(usuarioId)) {
    return nombresPorUsuario.get(usuarioId) ?? null;
  }

  try {
    const usuario = await prisma.usuario.findUnique({
      where: { id: usuarioId },
      select: { nombre: true },
    });
    const nombre = usuario?.nombre ?? null;
    nombresPorUsuario.set(usuarioId, nombre);
    return nombre;
  } catch {
    // Best-effort: el nombre es decorativo, el id y el rol ya identifican al actor.
    return null;
  }
}

/** Solo para pruebas y para invalidar el cache tras renombrar un usuario. */
export function limpiarCacheNombresAuditoria(): void {
  nombresPorUsuario.clear();
}

/** Texto legible de un actor, para descripciones de auditoria. */
export function describirActor(actor?: ActorAuditoria | null): string {
  if (!actor || (!actor.id && !actor.nombre)) return "el sistema";
  const nombre = actor.nombre?.trim();
  if (nombre) return actor.rol ? `${nombre} (${actor.rol})` : nombre;
  return actor.rol ? `${actor.id} (${actor.rol})` : String(actor.id);
}
