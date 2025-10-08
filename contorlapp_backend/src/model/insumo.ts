// src/models/insumo.ts
import { z } from "zod";

/** Dominio base 1:1 con Prisma */
export interface InsumoDominio {
  id: number;
  nombre: string;
  unidad: string;
  empresaId?: string | null;
}

/** Tipo público (igual por ahora) */
export type InsumoPublico = InsumoDominio;

/* ===================== DTOs ===================== */

/** Crear insumo (normalmente dentro del catálogo de una empresa) */
export const CrearInsumoDTO = z.object({
  nombre: z.string().min(2),
  unidad: z.string().min(1), // ej. "kg", "L", "unidad"
  empresaId: z.string().min(3).optional(),
});

/** Editar insumo */
export const EditarInsumoDTO = z.object({
  nombre: z.string().min(2).optional(),
  unidad: z.string().min(1).optional(),
  empresaId: z.string().min(3).optional().nullable(),
});

/** Filtro para búsquedas */
export const FiltroInsumoDTO = z.object({
  empresaId: z.string().optional(),
  nombre: z.string().optional(),
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const insumoPublicSelect = {
  id: true,
  nombre: true,
  unidad: true,
  empresaId: true,
} as const;

/** Helper para castear el resultado Prisma */
export function toInsumoPublico<
  T extends Record<keyof typeof insumoPublicSelect, any>
>(row: T): InsumoPublico {
  return row;
}
