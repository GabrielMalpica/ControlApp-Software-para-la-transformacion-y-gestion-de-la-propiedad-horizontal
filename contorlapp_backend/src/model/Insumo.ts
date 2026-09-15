import { z } from "zod";
import { CategoriaInsumo } from "@prisma/client";

/** Dominio base 1:1 con Prisma */
export interface InsumoDominio {
  id: number;
  nombre: string;
  unidad: string;
  categoria: CategoriaInsumo;
  umbralBajo?: number | null;
  empresaId?: string | null;
  conjuntoId?: string;
  contenidoPorUnidad?: number | null;
  unidadContenido?: string | null;
}

/** Tipo público (igual por ahora), más el flag derivado de si es personalizado */
export type InsumoPublico = InsumoDominio & { personalizado?: boolean };

/* ===================== DTOs ===================== */

/** Crear insumo (normalmente dentro del catálogo de una empresa) */
export const CrearInsumoDTO = z.object({
  nombre: z.string().min(2),
  unidad: z.string().min(1), // ej. "kg", "L", "unidad"
  categoria: z.nativeEnum(CategoriaInsumo),
  umbralBajo: z.coerce.number().int().min(0).optional(), // 👈 cambia aquí
  empresaId: z.string().min(3).optional(),
});

/** Crear insumo personalizado directamente en el inventario de un conjunto */
export const CrearInsumoPersonalizadoDTO = z
  .object({
    nombre: z.string().min(2),
    unidad: z.string().min(1), // texto libre: "tarro", "gal", "unidad", etc.
    categoria: z.nativeEnum(CategoriaInsumo),
    umbralBajo: z.coerce.number().int().min(0).optional(),
    cantidadInicial: z.coerce.number().min(0).optional(),
    // Contenido medible de CADA "unidad" (ej. cada tarro = 1.8 L). Opcionales,
    // pero si se envía uno se debe enviar el otro.
    contenidoPorUnidad: z.coerce.number().positive().optional(),
    unidadContenido: z.string().min(1).optional(),
  })
  .refine(
    (d) => Boolean(d.contenidoPorUnidad) === Boolean(d.unidadContenido),
    {
      message:
        "Si indicas el contenido por unidad, tambien debes indicar en que unidad se mide (y viceversa).",
      path: ["unidadContenido"],
    },
  );

/** Editar insumo personalizado (solo campos propios del conjunto) */
export const EditarInsumoPersonalizadoDTO = z
  .object({
    nombre: z.string().min(2).optional(),
    unidad: z.string().min(1).optional(),
    categoria: z.nativeEnum(CategoriaInsumo).optional(),
    umbralBajo: z.coerce.number().int().min(0).nullable().optional(),
    // Enviar ambos null limpia el contenido medible (vuelve a conteo simple).
    contenidoPorUnidad: z.coerce.number().positive().nullable().optional(),
    unidadContenido: z.string().min(1).nullable().optional(),
  })
  .refine(
    (d) =>
      d.contenidoPorUnidad === undefined && d.unidadContenido === undefined
        ? true
        : Boolean(d.contenidoPorUnidad) === Boolean(d.unidadContenido),
    {
      message:
        "Si indicas el contenido por unidad, tambien debes indicar en que unidad se mide (y viceversa).",
      path: ["unidadContenido"],
    },
  );

/** Editar insumo */
export const EditarInsumoDTO = z.object({
  nombre: z.string().min(2).optional(),
  unidad: z.string().min(1).optional(),
  categoria: z.nativeEnum(CategoriaInsumo).optional(),
  umbralBajo: z.coerce.number().int().min(0).optional(), // 👈 también aquí
  empresaId: z.string().min(3).optional().nullable(),
});

/** Filtro para búsquedas */
export const FiltroInsumoDTO = z.object({
  empresaId: z.string().optional(),
  nombre: z.string().optional(),
  categoria: z.nativeEnum(CategoriaInsumo).optional(),
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const insumoPublicSelect = {
  id: true,
  nombre: true,
  unidad: true,
  categoria: true,
  umbralBajo: true,
  empresaId: true,
  conjuntoId: true,
  contenidoPorUnidad: true,
  unidadContenido: true,
} as const;

/** Helper para castear el resultado Prisma */
export function toInsumoPublico<
  T extends Record<keyof typeof insumoPublicSelect, any>
>(row: T): InsumoPublico {
  return {
    ...(row as unknown as InsumoPublico),
    personalizado: Boolean(row.conjuntoId),
  };
}
