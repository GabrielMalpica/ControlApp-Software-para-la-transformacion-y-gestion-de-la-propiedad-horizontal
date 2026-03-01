// src/models/maquinaria.ts
import { z } from "zod";
import {
  EstadoMaquinaria,
  TipoMaquinaria,
  PropietarioMaquinaria,
  TipoTenenciaMaquinaria,
  EstadoAsignacionMaquinaria,
} from "@prisma/client";

/* ===================== DOMINIO ===================== */

// ✅ Catálogo/Activo (tabla Maquinaria)
export interface MaquinariaCatalogo {
  id: number;
  nombre: string;
  marca: string;
  tipo: TipoMaquinaria;
  estado: EstadoMaquinaria;

  propietarioTipo: PropietarioMaquinaria; // REQUIRED
  empresaId?: string | null;
  conjuntoPropietarioId?: string | null;

  operarioId?: string | null; // Operario.id es String en tu schema
}

// ✅ Inventario de maquinaria por conjunto (tabla MaquinariaConjunto)
export interface MaquinariaInventarioConjunto {
  id: number;
  conjuntoId: string;
  maquinariaId: number;
  tipoTenencia: TipoTenenciaMaquinaria;
  estado: EstadoAsignacionMaquinaria;

  fechaInicio: Date;
  fechaFin?: Date | null;
  fechaDevolucionEstimada?: Date | null;

  operarioId?: string | null; // responsable en esa asignación
}

/* ===================== DTOs ===================== */

// Crear maquinaria del catálogo de empresa
export const CrearMaquinariaCatalogoDTO = z.object({
  nombre: z.string().min(2),
  marca: z.string().min(2),
  tipo: z.nativeEnum(TipoMaquinaria),
  estado: z
    .nativeEnum(EstadoMaquinaria)
    .optional()
    .default(EstadoMaquinaria.OPERATIVA),

  // para catálogo empresa:
  empresaId: z.string().min(3),

  // opcional: responsable global (en Maquinaria)
  operarioId: z.string().optional(),
});

export const CrearMaquinariaDTO = z.object({
  nombre: z.string().min(2),
  marca: z.string().min(2),
  tipo: z.nativeEnum(TipoMaquinaria),
  estado: z
    .nativeEnum(EstadoMaquinaria)
    .optional()
    .default(EstadoMaquinaria.OPERATIVA),

  // ✅ NUEVO: dueño
  propietarioTipo: z
    .nativeEnum(PropietarioMaquinaria)
    .default(PropietarioMaquinaria.EMPRESA),
  conjuntoPropietarioId: z.string().min(3).optional().nullable(), // nit si dueño = CONJUNTO
});

// Editar maquinaria del catálogo
export const EditarMaquinariaCatalogoDTO = z.object({
  nombre: z.string().min(2).optional(),
  marca: z.string().min(2).optional(),
  tipo: z.nativeEnum(TipoMaquinaria).optional(),
  estado: z.nativeEnum(EstadoMaquinaria).optional(),
  operarioId: z.string().optional().nullable(),
});

// Asignar (prestar) maquinaria al inventario de un conjunto
export const PrestarMaquinariaAConjuntoDTO = z.object({
  maquinariaId: z.number().int().positive(),
  conjuntoId: z.string().min(3),
  fechaDevolucionEstimada: z.coerce.date().optional(),
  operarioId: z.string().optional(), // responsable de la asignación
});

// Devolver maquinaria del conjunto (cerrar asignación ACTIVA)
export const DevolverMaquinariaDeConjuntoDTO = z.object({
  maquinariaId: z.number().int().positive(),
  conjuntoId: z.string().min(3),
});

export const FiltroMaquinariaDTO = z.object({
  empresaId: z.string().optional(),
  conjuntoId: z.string().optional(), // filtra por "prestada a este conjunto" (asignación ACTIVA)
  estado: z.nativeEnum(EstadoMaquinaria).optional(),
  disponible: z.boolean().optional(), // derivado
  tipo: z.nativeEnum(TipoMaquinaria).optional(),

  // ✅ NUEVO: filtrar por origen/dueño
  propietarioTipo: z.nativeEnum(PropietarioMaquinaria).optional(), // EMPRESA | CONJUNTO
});

/* ===================== SELECTS ===================== */

export const maquinariaCatalogoSelect = {
  id: true,
  nombre: true,
  marca: true,
  tipo: true,
  estado: true,
  propietarioTipo: true,
  empresaId: true,
  conjuntoPropietarioId: true,
  operarioId: true,
} as const;

export const maquinariaConjuntoSelect = {
  id: true,
  conjuntoId: true,
  maquinariaId: true,
  tipoTenencia: true,
  estado: true,
  fechaInicio: true,
  fechaFin: true,
  fechaDevolucionEstimada: true,
  operarioId: true,
  maquinaria: {
    select: { id: true, nombre: true, marca: true, tipo: true, estado: true },
  },
} as const;
