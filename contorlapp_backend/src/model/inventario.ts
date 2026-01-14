// src/models/inventarioInsumo.ts
import { z } from "zod";
import { CategoriaInsumo } from "../generated/prisma";
import { decToNumber } from "../utils/decimal";

/** Dominio 1:1 con Prisma */
export interface InventarioInsumoDominio {
  id: number;
  inventarioId: number;
  insumoId: number;
  cantidad: number;
  umbralMinimo?: number | null; // override por conjunto (opcional)
}

/** Tipo público */
export type InventarioInsumoPublico = InventarioInsumoDominio;

/* ===================== DTOs ===================== */

/** Agregar stock (incrementa) */
export const AgregarStockDTO = z.object({
  inventarioId: z.number().int().positive(),
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

/** Consumir stock (decrementa) */
export const ConsumirStockDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.coerce.number().positive(),
});


/** Fijar/actualizar umbral mínimo (por conjunto) */
export const SetUmbralMinimoDTO = z.object({
  inventarioId: z.number().int().positive(),
  insumoId: z.number().int().positive(),
  umbralMinimo: z.coerce.number().int().min(0),
});

/** Quitar umbral mínimo (para volver a usar el global del insumo si existe) */
export const UnsetUmbralMinimoDTO = z.object({
  inventarioId: z.number().int().positive(),
  insumoId: z.number().int().positive(),
});

/** Filtro para listar insumos bajos */
export const InsumosBajosFiltroDTO = z.object({
  inventarioId: z.number().int().positive(),
  categoria: z.nativeEnum(CategoriaInsumo).optional(), // opcional: filtrar por categoría
  nombre: z.string().optional(),                        // opcional: filtro por texto
});

/* ===================== SELECTS ===================== */

export const inventarioInsumoPublicSelect = {
  id: true,
  inventarioId: true,
  insumoId: true,
  cantidad: true,
  umbralMinimo: true,
} as const;

/** Helper */
export function toInventarioInsumoPublico(row: any): InventarioInsumoPublico {
  return {
    id: row.id,
    inventarioId: row.inventarioId,
    insumoId: row.insumoId,
    cantidad: decToNumber(row.cantidad),
    umbralMinimo: row.umbralMinimo != null ? decToNumber(row.umbralMinimo) : null,
  };
}
