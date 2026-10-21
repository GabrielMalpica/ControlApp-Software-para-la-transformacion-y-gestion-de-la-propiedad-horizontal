// src/aplicacion/alcanceConjuntos.ts
import type { PrismaClient } from "@prisma/client";

/**
 * Conjuntos que un usuario puede consultar dentro de su empresa.
 * - `null`: sin restricción, toda la empresa (gerente, jefe de operaciones,
 *   supervisor y operario).
 * - lista: solo esos NIT. El administrador es el cliente dueño de sus
 *   conjuntos (`Conjunto.administradorId`) y no ve los de otros clientes.
 *
 * No depende de Express: los controllers y cualquier otra entrada (p. ej. un
 * MCP) resuelven el alcance igual y lo pasan a los servicios.
 */
export type AlcanceConjuntos = string[] | null;

export type UsuarioAlcance = {
  usuarioId: string;
  rol: string;
  empresaId: string;
};

type PrismaAlcance = {
  conjunto: Pick<PrismaClient["conjunto"], "findMany">;
  residente: Pick<PrismaClient["residente"], "findFirst">;
};

type HttpError = Error & { status: number };

// Roles internos de la empresa: ven todos sus conjuntos. El operario no tiene
// reportes ni asistencia por defecto; si se le conceden, conserva el alcance
// de empresa que ya tenía (igual que requireConjuntoScope).
const ROLES_SIN_RESTRICCION = new Set([
  "gerente",
  "jefe_operaciones",
  "supervisor",
  "operario",
]);

export async function alcanceConjuntos(
  prisma: PrismaAlcance,
  usuario: UsuarioAlcance,
): Promise<AlcanceConjuntos> {
  const rol = usuario.rol.trim().toLowerCase();
  if (ROLES_SIN_RESTRICCION.has(rol)) return null;

  if (rol === "administrador") {
    const conjuntos = await prisma.conjunto.findMany({
      where: { administradorId: usuario.usuarioId, empresaId: usuario.empresaId },
      select: { nit: true },
      orderBy: { nit: "asc" },
    });
    return conjuntos.map((c) => c.nit);
  }

  if (rol === "residente") {
    const residente = await prisma.residente.findFirst({
      where: { id: usuario.usuarioId, conjunto: { empresaId: usuario.empresaId } },
      select: { conjuntoId: true },
    });
    return residente ? [residente.conjuntoId] : [];
  }

  // Rol desconocido: sin conjuntos.
  return [];
}

export function conjuntoEnAlcance(alcance: AlcanceConjuntos, conjuntoId: string): boolean {
  return alcance === null || alcance.includes(conjuntoId);
}

/**
 * Un conjunto pedido fuera del alcance responde 404 (recurso ajeno = no
 * encontrado, para no revelar que existe). Sin conjunto no hay nada que validar.
 */
export function exigirConjuntoEnAlcance(
  alcance: AlcanceConjuntos,
  conjuntoId: string | null | undefined,
): void {
  if (!conjuntoId) return;
  if (!conjuntoEnAlcance(alcance, conjuntoId)) {
    const error = new Error("Recurso no encontrado") as HttpError;
    error.status = 404;
    throw error;
  }
}

/**
 * Filtro Prisma por `conjuntoId`: el conjunto pedido, o todos los del alcance
 * si no se pidió ninguno. Un conjunto fuera del alcance nunca coincide.
 */
export function filtroConjuntoEnAlcance(
  alcance: AlcanceConjuntos,
  conjuntoId?: string | null,
): { conjuntoId?: string | { in: string[] } } {
  if (conjuntoId) {
    return { conjuntoId: conjuntoEnAlcance(alcance, conjuntoId) ? conjuntoId : { in: [] } };
  }
  return alcance === null ? {} : { conjuntoId: { in: alcance } };
}

/** Parte de una clave de caché/deduplicación que distingue alcances. */
export function claveAlcance(alcance: AlcanceConjuntos): string {
  return alcance === null ? "*" : [...alcance].sort().join(",") || "-";
}
