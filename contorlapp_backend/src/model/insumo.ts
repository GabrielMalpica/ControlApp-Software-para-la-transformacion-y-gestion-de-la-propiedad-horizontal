import { z } from "zod";
import { CategoriaInsumo } from "../generated/prisma";

/** Dominio base 1:1 con Prisma */
export interface InsumoDominio {
  id: number;
  nombre: string;
  unidad: string;
  categoria: CategoriaInsumo;          // NUEVO
  umbralGlobalMinimo?: number | null;  // NUEVO
  empresaId?: string | null;
}

/** Tipo público (igual por ahora) */
export type InsumoPublico = InsumoDominio;

/* ===================== DTOs ===================== */

/** Crear insumo (normalmente dentro del catálogo de una empresa) */
export const CrearInsumoDTO = z.object({
  nombre: z.string().min(2),
  unidad: z.string().min(1), // ej. "kg", "L", "unidad"
  categoria: z.nativeEnum(CategoriaInsumo),          // NUEVO (requerido)
  umbralGlobalMinimo: z.coerce.number().int().min(0).optional(), // NUEVO
  empresaId: z.string().min(3).optional(),
});

/** Editar insumo */
export const EditarInsumoDTO = z.object({
  nombre: z.string().min(2).optional(),
  unidad: z.string().min(1).optional(),
  categoria: z.nativeEnum(CategoriaInsumo).optional(),          // NUEVO
  umbralGlobalMinimo: z.coerce.number().int().min(0).optional(), // NUEVO
  empresaId: z.string().min(3).optional().nullable(),
});

/** Filtro para búsquedas */
export const FiltroInsumoDTO = z.object({
  empresaId: z.string().optional(),
  nombre: z.string().optional(),
  categoria: z.nativeEnum(CategoriaInsumo).optional(), // NUEVO
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const insumoPublicSelect = {
  id: true,
  nombre: true,
  unidad: true,
  categoria: true,            // NUEVO
  umbralGlobalMinimo: true,   // NUEVO
  empresaId: true,
} as const;

/** Helper para castear el resultado Prisma */
export function toInsumoPublico<
  T extends Record<keyof typeof insumoPublicSelect, any>
>(row: T): InsumoPublico {
  return row as unknown as InsumoPublico;
}
