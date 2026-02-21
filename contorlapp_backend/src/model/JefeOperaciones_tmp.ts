// src/models/jefeOperaciones.ts
import { z } from "zod";

/** Dominio base según Prisma */
export interface JefeOperacionesDominio {
  id: number;          // mismo ID que Usuario.id
}

/** Tipo público (igual por ahora) */
export type JefeOperacionesPublico = JefeOperacionesDominio;

/* ===================== DTOs ===================== */

/** Crear jefe de operaciones */
export const CrearJefeOperacionesDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});

/** Editar jefe de operaciones (solo empresa, opcional) */
export const EditarJefeOperacionesDTO = z.object({
  empresaId: z.string().min(3).optional(),
});

/* ===================== SELECT BASE ===================== */
export const jefeOperacionesPublicSelect = {
  id: true,
  empresaId: true,
} as const;

/** Helper para mapear resultado de Prisma */
export function toJefeOperacionesPublico<
  T extends Record<keyof typeof jefeOperacionesPublicSelect, any>
>(row: T): JefeOperacionesPublico {
  return row;
}
