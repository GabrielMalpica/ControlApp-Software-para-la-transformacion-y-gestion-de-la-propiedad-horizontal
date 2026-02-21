// src/models/ubicacion.ts
import { z } from "zod";

/** Dominio base 1:1 con Prisma */
export interface UbicacionDominio {
  id: number;
  nombre: string;
  conjuntoId: string; // nit del conjunto
}

/** Tipo público (idéntico) */
export type UbicacionPublica = UbicacionDominio;

/* ===================== DTOs ===================== */

/** Crear ubicación dentro de un conjunto */
export const CrearUbicacionDTO = z.object({
  nombre: z.string().min(2),
  conjuntoId: z.string().min(3),
});

/** Editar ubicación (solo nombre por ahora) */
export const EditarUbicacionDTO = z.object({
  nombre: z.string().min(2).optional(),
});

/** Filtro de búsqueda de ubicaciones */
export const FiltroUbicacionDTO = z.object({
  conjuntoId: z.string().min(3).optional(),
  nombre: z.string().optional(),
});

/* ===================== SELECT BASE ===================== */
export const ubicacionPublicSelect = {
  id: true,
  nombre: true,
  conjuntoId: true,
} as const;

/** Helper para castear select a tipo público */
export function toUbicacionPublica<
  T extends Record<keyof typeof ubicacionPublicSelect, any>
>(row: T): UbicacionPublica {
  return row;
}
