// src/models/inventario.ts
import { z } from "zod";

/** Dominio base 1:1 con Prisma */
export interface InventarioDominio {
  id: number;
  conjuntoId: string; // NIT del conjunto (único)
}

/** Tipo público (igual por ahora) */
export type InventarioPublico = InventarioDominio;

/* ===================== DTOs ===================== */

/** Crear inventario para un conjunto (solo uno por conjunto según Prisma) */
export const CrearInventarioDTO = z.object({
  conjuntoId: z.string().min(3),
});

/** Editar inventario (normalmente no se edita, pero se deja por consistencia) */
export const EditarInventarioDTO = z.object({
  conjuntoId: z.string().min(3).optional(),
});

/** Filtro de inventarios */
export const FiltroInventarioDTO = z.object({
  conjuntoId: z.string().optional(),
});

/* ===================== SELECT BASE ===================== */
export const inventarioPublicSelect = {
  id: true,
  conjuntoId: true,
} as const;

/** Helper para castear el resultado Prisma */
export function toInventarioPublico<
  T extends Record<keyof typeof inventarioPublicSelect, any>
>(row: T): InventarioPublico {
  return row;
}
