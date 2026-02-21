// src/models/elemento.ts
import { z } from "zod";

/** Dominio base 1:1 con Prisma */
export interface ElementoDominio {
  id: number;
  nombre: string;
  ubicacionId: number;
}

/** Tipo público (idéntico) */
export type ElementoPublico = ElementoDominio;

/* ===================== DTOs ===================== */

/** Crear elemento dentro de una ubicación */
export const CrearElementoDTO = z.object({
  nombre: z.string().min(2),
  ubicacionId: z.number().int().positive(),
});

/** Editar elemento (solo nombre por ahora) */
export const EditarElementoDTO = z.object({
  nombre: z.string().min(2).optional(),
});

/** Filtro de búsqueda de elementos */
export const FiltroElementoDTO = z.object({
  ubicacionId: z.number().int().optional(),
  nombre: z.string().optional(),
});

/* ===================== SELECT BASE ===================== */
export const elementoPublicSelect = {
  id: true,
  nombre: true,
  ubicacionId: true,
} as const;

/** Helper para castear select a tipo público */
export function toElementoPublico<
  T extends Record<keyof typeof elementoPublicSelect, any>
>(row: T): ElementoPublico {
  return row;
}
