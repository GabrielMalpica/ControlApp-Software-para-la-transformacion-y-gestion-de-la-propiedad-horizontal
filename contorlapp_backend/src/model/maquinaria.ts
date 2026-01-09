// src/models/maquinaria.ts
import { z } from "zod";
import {
  EstadoMaquinaria,
  TipoMaquinaria,
} from "../generated/prisma"; // enums Prisma

/** Dominio base 1:1 con Prisma */
export interface MaquinariaDominio {
  id: number;
  nombre: string;
  marca: string;
  tipo: TipoMaquinaria;
  estado: EstadoMaquinaria;
  disponible: boolean;
  conjuntoId?: string | null;   // NIT del conjunto donde está asignada
  operarioId?: number | null;   // responsable
  empresaId?: string | null;    // empresa dueña
  fechaPrestamo?: Date | null;
  fechaDevolucionEstimada?: Date | null;
  conjuntoNombre?: string | null;
  operarioNombre?: string | null;
}

/** Tipo público (idéntico por ahora) */
export type MaquinariaPublica = MaquinariaDominio;

/* ===================== DTOs ===================== */

/** Crear maquinaria (parte del stock de empresa) */
export const CrearMaquinariaDTO = z.object({
  nombre: z.string().min(2),
  marca: z.string().min(2),
  tipo: z.nativeEnum(TipoMaquinaria),
  estado: z.nativeEnum(EstadoMaquinaria).optional().default(EstadoMaquinaria.OPERATIVA),
  disponible: z.boolean().optional().default(true),
  conjuntoId: z.string().min(3).optional(),
  operarioId: z.number().int().optional(),
  empresaId: z.string().min(3).optional(),
  fechaPrestamo: z.coerce.date().optional(),
  fechaDevolucionEstimada: z.coerce.date().optional(),
});

/** Editar maquinaria */
export const EditarMaquinariaDTO = z.object({
  nombre: z.string().min(2).optional(),
  marca: z.string().min(2).optional(),
  tipo: z.nativeEnum(TipoMaquinaria).optional(),
  estado: z.nativeEnum(EstadoMaquinaria).optional(),
  disponible: z.boolean().optional(),
  conjuntoId: z.string().min(3).optional().nullable(),
  operarioId: z.number().int().optional().nullable(),
  empresaId: z.string().min(3).optional().nullable(),
  fechaPrestamo: z.coerce.date().optional().nullable(),
  fechaDevolucionEstimada: z.coerce.date().optional().nullable(),
});

/** Filtro de búsqueda (para listados, reportes, etc.) */
export const FiltroMaquinariaDTO = z.object({
  empresaId: z.string().optional(),
  conjuntoId: z.string().optional(),
  estado: z.nativeEnum(EstadoMaquinaria).optional(),
  disponible: z.boolean().optional(),
  tipo: z.nativeEnum(TipoMaquinaria).optional(),
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const maquinariaPublicSelect = {
  id: true,
  nombre: true,
  marca: true,
  tipo: true,
  estado: true,
  disponible: true,
  conjuntoId: true,
  operarioId: true,
  empresaId: true,
  fechaPrestamo: true,
  fechaDevolucionEstimada: true,
} as const;

/** Helper para castear el resultado de Prisma al tipo público */
export function toMaquinariaPublica<
  T extends Record<keyof typeof maquinariaPublicSelect, any>
>(row: T): MaquinariaPublica {
  return row;
}
