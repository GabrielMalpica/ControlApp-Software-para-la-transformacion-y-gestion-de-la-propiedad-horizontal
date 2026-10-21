// src/models/supervisor.ts
import { z } from "zod";

import { camposFueraDeEdicionRapida, EditarUsuarioDTO } from "./Usuario";

/** Dominio base según Prisma */
export interface SupervisorDominio {
  id: string; // mismo ID que Usuario.id
}

/** Tipo público (igual por ahora) */
export type SupervisorPublico = SupervisorDominio;

/* ===================== DTOs ===================== */

/** Crear supervisor */
export const CrearSupervisorDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});

/**
 * Edicion rapida (PATCH /gerente/supervisores/:id): nombre y correo. La empresa
 * del supervisor no se mueve desde el cliente: siempre es la de la sesion.
 */
export const EditarSupervisorDTO = z.object({
  nombre: EditarUsuarioDTO.shape.nombre,
  correo: EditarUsuarioDTO.shape.correo,
  ...camposFueraDeEdicionRapida,
});

export const VeredictoSupervisorDTO = z.object({
  estado: z.enum(["APROBADA", "RECHAZADA", "NO_COMPLETADA"]),
  observacionesRechazo: z.string().min(3).max(500).optional(),
  evidencias: z.array(z.string()).default([]), // si el supervisor sube fotos al aprobar/rechazar
});

/* ===================== SELECT BASE ===================== */
export const supervisorPublicSelect = {
  id: true,
  empresaId: true,
} as const;

/** Helper para castear select de Prisma */
export function toSupervisorPublico<
  T extends Record<keyof typeof supervisorPublicSelect, any>,
>(row: T): SupervisorPublico {
  return row;
}
