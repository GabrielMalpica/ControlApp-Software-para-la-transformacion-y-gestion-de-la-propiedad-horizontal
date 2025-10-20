// src/model/DefinicionTareaPreventiva.ts
import { z } from "zod";
import { Frecuencia, UnidadCalculo } from "../generated/prisma";

/** Dominio base 1:1 con Prisma */
export interface DefinicionTareaPreventivaDominio {
  id: number;
  conjuntoId: string;

  ubicacionId: number;
  elementoId: number;

  descripcion: string;
  frecuencia: Frecuencia;
  prioridad: number;

  // En Prisma son Decimal; aquí los exponemos como number
  unidadCalculo?: UnidadCalculo | null;
  areaNumerica?: number | null;
  rendimientoBase?: number | null;

  duracionHorasFija?: number | null;

  insumoPrincipalId?: number | null;
  consumoPrincipalPorUnidad?: number | null;

  // Json en Prisma; aquí definimos una forma simple y validable
  insumosPlanJson?:
    | {
        insumoId: number;
        consumoPorUnidad: number; // por unidadCalculo (ej. litros por m2)
      }[]
    | null;

  maquinariaPlanJson?:
    | {
        maquinariaId?: number; // si apuntas a una máquina particular
        tipo?: string; // o un tipo genérico si no hay id
        cantidad?: number; // opcional (por bloque o por día)
      }[]
    | null;

  responsableSugeridoId?: number | null;

  activo: boolean;
  creadoEn: Date;
  actualizadoEn: Date;
}

/** Tipo público — igual por ahora */
export type DefinicionTareaPreventivaPublica =
  DefinicionTareaPreventivaDominio;

/* ===================== DTOs ===================== */

const InsumoPlanItemDTO = z.object({
  insumoId: z.number().int().positive(),
  consumoPorUnidad: z.coerce.number().min(0),
});

const MaquinariaPlanItemDTO = z.object({
  maquinariaId: z.number().int().positive().optional(),
  tipo: z.string().min(1).optional(),
  cantidad: z.coerce.number().min(0).optional(),
});

/** Crear definición (molde) de tarea preventiva */
export const CrearDefinicionPreventivaDTO = z
  .object({
    conjuntoId: z.string().min(3),

    ubicacionId: z.number().int().positive(),
    elementoId: z.number().int().positive(),

    descripcion: z.string().min(3),
    frecuencia: z.nativeEnum(Frecuencia),
    prioridad: z.number().int().min(1).max(9).default(5),

    // A) cálculo por rendimiento/área (opcional)
    unidadCalculo: z.nativeEnum(UnidadCalculo).optional(),
    areaNumerica: z.coerce.number().min(0).optional(),
    rendimientoBase: z.coerce.number().min(0).optional(),

    // B) duración fija (opcional)
    duracionHorasFija: z.number().int().positive().optional(),

    // Recursos planeados
    insumoPrincipalId: z.number().int().positive().optional(),
    consumoPrincipalPorUnidad: z.coerce.number().min(0).optional(),

    insumosPlanJson: z.array(InsumoPlanItemDTO).optional(),
    maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional(),

    responsableSugeridoId: z.number().int().positive().optional(),

    activo: z.boolean().default(true),
  })
  .refine(
    (d) => {
      // Debe definirse o (área+rendimiento) o (duración fija)
      const tieneRendimiento =
        d.unidadCalculo &&
        d.areaNumerica !== undefined &&
        d.rendimientoBase !== undefined;
      const tieneDuracionFija = d.duracionHorasFija !== undefined;
      return tieneRendimiento || tieneDuracionFija;
    },
    {
      message:
        "Debe indicar (unidadCalculo + areaNumerica + rendimientoBase) o duracionHorasFija.",
    }
  );

/** Editar definición preventiva (todo opcional) */
export const EditarDefinicionPreventivaDTO = z
  .object({
    ubicacionId: z.number().int().positive().optional(),
    elementoId: z.number().int().positive().optional(),

    descripcion: z.string().min(3).optional(),
    frecuencia: z.nativeEnum(Frecuencia).optional(),
    prioridad: z.number().int().min(1).max(9).optional(),

    unidadCalculo: z.nativeEnum(UnidadCalculo).optional().nullable(),
    areaNumerica: z.coerce.number().min(0).optional().nullable(),
    rendimientoBase: z.coerce.number().min(0).optional().nullable(),

    duracionHorasFija: z.number().int().positive().optional().nullable(),

    insumoPrincipalId: z.number().int().positive().optional().nullable(),
    consumoPrincipalPorUnidad: z.coerce.number().min(0).optional().nullable(),

    insumosPlanJson: z.array(InsumoPlanItemDTO).optional().nullable(),
    maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional().nullable(),

    responsableSugeridoId: z.number().int().positive().optional().nullable(),

    activo: z.boolean().optional(),
  })
  // Validación blanda: si setean uno de A, deben setear los otros (o limpiar todos y usar duración fija)
  .refine(
    (d) => {
      const algunoA =
        d.unidadCalculo !== undefined ||
        d.areaNumerica !== undefined ||
        d.rendimientoBase !== undefined;
      if (!algunoA) return true;
      // Si toca A, que vengan los tres (o null para limpiar)
      const okA =
        d.unidadCalculo !== undefined &&
        d.areaNumerica !== undefined &&
        d.rendimientoBase !== undefined;
      return okA;
    },
    {
      message:
        "Si modifica cálculo por rendimiento, incluya unidadCalculo, areaNumerica y rendimientoBase.",
    }
  );

/** Filtro para listar/consultar definiciones */
export const FiltroDefinicionPreventivaDTO = z.object({
  conjuntoId: z.string().min(3),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional(),
  activo: z.boolean().optional(),
});

/** DTO para generar el cronograma/borrador mensual */
export const GenerarCronogramaDTO = z.object({
  conjuntoId: z.string().min(3),
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12), // 1..12
  tamanoBloqueHoras: z.coerce.number().int().min(1).max(12).optional(), // default 1h
});

// Alias opcional por compatibilidad si en algún lugar lo importaste con otro nombre
export const GenerarCronogramaMensualDTO = GenerarCronogramaDTO;

/* ===================== SELECT PARA PRISMA ===================== */

export const definicionPreventivaPublicSelect = {
  id: true,
  conjuntoId: true,

  ubicacionId: true,
  elementoId: true,

  descripcion: true,
  frecuencia: true,
  prioridad: true,

  unidadCalculo: true,
  areaNumerica: true,
  rendimientoBase: true,

  duracionHorasFija: true,

  insumoPrincipalId: true,
  consumoPrincipalPorUnidad: true,

  insumosPlanJson: true,
  maquinariaPlanJson: true,

  responsableSugeridoId: true,

  activo: true,
  creadoEn: true,
  actualizadoEn: true,
} as const;

/** Helper para castear el resultado Prisma al tipo público */
export function toDefinicionTareaPreventivaPublica<
  T extends Record<keyof typeof definicionPreventivaPublicSelect, any>
>(row: T): DefinicionTareaPreventivaPublica {
  return row as unknown as DefinicionTareaPreventivaPublica;
}

/* ===================== Utilidad ===================== */
/**
 * Calcula horas estimadas dado área y rendimiento.
 */
export function calcularHorasEstimadas(params: {
  areaNumerica?: number | null;
  rendimientoBase?: number | null; // ej. 100 m2/h
  duracionHorasFija?: number | null;
}): number | null {
  if (params?.duracionHorasFija != null) return params.duracionHorasFija;
  if (params?.areaNumerica != null && params?.rendimientoBase) {
    if (params.rendimientoBase <= 0) return null;
    return params.areaNumerica / params.rendimientoBase;
  }
  return null;
}
