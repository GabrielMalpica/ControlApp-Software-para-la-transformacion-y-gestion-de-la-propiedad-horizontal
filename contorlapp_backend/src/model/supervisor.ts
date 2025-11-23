// src/models/supervisor.ts
import { z } from "zod";

/** Dominio base según Prisma */
export interface SupervisorDominio {
  id: number;          // mismo ID que Usuario.id
}

/** Tipo público (igual por ahora) */
export type SupervisorPublico = SupervisorDominio;

/* ===================== DTOs ===================== */

/** Crear supervisor */
export const CrearSupervisorDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});

/** Editar supervisor (solo empresa por ahora) */
export const EditarSupervisorDTO = z.object({
  empresaId: z.string().min(3).optional(),
});

/* ===================== SELECT BASE ===================== */
export const supervisorPublicSelect = {
  id: true,
  empresaId: true,
} as const;

/** Helper para castear select de Prisma */
export function toSupervisorPublico<
  T extends Record<keyof typeof supervisorPublicSelect, any>
>(row: T): SupervisorPublico {
  return row;
}
