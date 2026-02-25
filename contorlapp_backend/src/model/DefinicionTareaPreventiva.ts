// src/model/DefinicionTareaPreventiva.ts
import { z } from "zod";
import { DiaSemana, Frecuencia, UnidadCalculo } from "@prisma/client";

/** Dominio base 1:1 (aprox) con Prisma */
export interface DefinicionTareaPreventivaDominio {
  id: number;
  conjuntoId: string;

  ubicacionId: number;
  elementoId: number;

  descripcion: string;
  frecuencia: Frecuencia;
  prioridad: number;

  diaSemanaProgramado?: DiaSemana | null;
  diaMesProgramado?: number | null;

  unidadCalculo?: UnidadCalculo | null;
  areaNumerica?: number | null;
  rendimientoBase?: number | null;

  /** "POR_MINUTO" o "POR_HORA" (según tu BD) */
  rendimientoTiempoBase?: "POR_MINUTO" | "POR_HORA" | null;

  duracionMinutosFija?: number | null;
  diasParaCompletar?: number | null;

  insumoPrincipalId?: number | null;
  consumoPrincipalPorUnidad?: number | null;

  insumosPlanJson?:
    | {
        insumoId: number;
        consumoPorUnidad: number;
      }[]
    | null;

  maquinariaPlanJson?:
    | {
        maquinariaId?: number;
        tipo?: string;
        cantidad?: number;
      }[]
    | null;

  herramientasPlanJson?:
    | {
        herramientaId: number;
        cantidad?: number;
      }[]
    | null;

  activo: boolean;
  creadoEn: Date;
  actualizadoEn: Date;
}

/** Tipo público — igual por ahora */
export type DefinicionTareaPreventivaPublica = DefinicionTareaPreventivaDominio;

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

const HerramientaPlanItemDTO = z.object({
  herramientaId: z.number().int().positive(),
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

    prioridad: z.number().int().min(1).max(3).default(2),

    // programación específica
    diaSemanaProgramado: z.nativeEnum(DiaSemana).optional().nullable(),
    diaMesProgramado: z.number().int().min(1).max(31).optional().nullable(),

    // A) rendimiento/área
    unidadCalculo: z.nativeEnum(UnidadCalculo).optional().nullable(),
    areaNumerica: z.coerce.number().min(0).optional(),
    rendimientoBase: z.coerce.number().min(0).optional(),

    // 👇 sin enums nuevos: literal union
    rendimientoTiempoBase: z.enum(["POR_MINUTO", "POR_HORA"]).optional(),

    // B) duración fija
    duracionMinutosFija: z.number().int().min(1).optional(),
    diasParaCompletar: z.number().int().min(1).max(31).optional().nullable(),

    // compat temporal
    duracionHorasFija: z.coerce.number().positive().optional(),

    insumoPrincipalId: z.number().int().positive().optional(),
    consumoPrincipalPorUnidad: z.coerce.number().min(0).optional(),

    insumosPlanJson: z.array(InsumoPlanItemDTO).optional(),
    maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional(),
    herramientasPlanJson: z.array(HerramientaPlanItemDTO).optional(),

    responsableSugeridoId: z.number().int().positive().optional(),
    operariosIds: z.array(z.number().int().positive()).optional(),

    supervisorId: z.number().int().positive().optional(),

    activo: z.boolean().default(true),
  })
  .refine(
    (d) => {
      const tieneRendimiento =
        !!d.unidadCalculo &&
        d.areaNumerica !== undefined &&
        d.rendimientoBase !== undefined;

      const tieneDuracionMin = d.duracionMinutosFija !== undefined;
      const tieneDuracionHoras = d.duracionHorasFija !== undefined;

      return tieneRendimiento || tieneDuracionMin || tieneDuracionHoras;
    },
    {
      message:
        "Debe indicar (unidadCalculo + areaNumerica + rendimientoBase) o duracionMinutosFija (o duracionHorasFija compat).",
    },
  );

/** Editar definición preventiva (todo opcional) */
export const EditarDefinicionPreventivaDTO = z.object({
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),

  descripcion: z.string().min(3).optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional(),
  prioridad: z.number().int().min(1).max(3).optional(),

  diaSemanaProgramado: z.nativeEnum(DiaSemana).optional().nullable(),
  diaMesProgramado: z.number().int().min(1).max(31).optional().nullable(),

  unidadCalculo: z.nativeEnum(UnidadCalculo).optional().nullable(),
  areaNumerica: z.coerce.number().min(0).optional().nullable(),
  rendimientoBase: z.coerce.number().min(0).optional().nullable(),

  rendimientoTiempoBase: z
    .enum(["POR_MINUTO", "POR_HORA"])
    .optional()
    .nullable(),

  duracionMinutosFija: z.number().int().min(1).optional().nullable(),
  diasParaCompletar: z.number().int().min(1).max(31).optional().nullable(),
  duracionHorasFija: z.coerce.number().positive().optional().nullable(),

  insumoPrincipalId: z.number().int().positive().optional().nullable(),
  consumoPrincipalPorUnidad: z.coerce.number().min(0).optional().nullable(),

  insumosPlanJson: z.array(InsumoPlanItemDTO).optional().nullable(),
  maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional().nullable(),
  herramientasPlanJson: z.array(HerramientaPlanItemDTO).optional().nullable(),

  responsableSugeridoId: z.number().int().positive().optional().nullable(),
  operariosIds: z.array(z.number().int().positive()).optional().nullable(),

  supervisorId: z.number().int().positive().optional().nullable(),
  activo: z.boolean().optional(),
});

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
  mes: z.coerce.number().int().min(1).max(12),
  tamanoBloqueHoras: z.coerce.number().positive().max(12).optional(),
  tamanoBloqueMinutos: z.coerce
    .number()
    .int()
    .min(1)
    .max(12 * 60)
    .optional(),
});

// Alias opcional por compatibilidad
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

  diaSemanaProgramado: true,
  diaMesProgramado: true,

  unidadCalculo: true,
  areaNumerica: true,
  rendimientoBase: true,
  rendimientoTiempoBase: true,

  duracionMinutosFija: true,
  diasParaCompletar: true,

  insumoPrincipalId: true,
  consumoPrincipalPorUnidad: true,

  insumosPlanJson: true,
  maquinariaPlanJson: true,
  herramientasPlanJson: true,

  activo: true,
  creadoEn: true,
  actualizadoEn: true,
} as const;

/** Helper para castear el resultado Prisma al tipo público */
export function toDefinicionTareaPreventivaPublica<
  T extends Record<keyof typeof definicionPreventivaPublicSelect, any>,
>(row: T): DefinicionTareaPreventivaPublica {
  return row as unknown as DefinicionTareaPreventivaPublica;
}

/* ===================== Utilidad ===================== */
/**
 * Calcula minutos estimados dado área y rendimiento.
 */
export function calcularMinutosEstimados(params: {
  cantidad?: number; // areaNumerica
  rendimiento?: number; // rendimientoBase
  duracionMinutosFija?: number;
  rendimientoTiempoBase?: "POR_MINUTO" | "POR_HORA";
}): number | null {
  const {
    cantidad,
    rendimiento,
    duracionMinutosFija,
    rendimientoTiempoBase = "POR_HORA",
  } = params;

  if (duracionMinutosFija != null)
    return Math.max(1, Math.round(duracionMinutosFija));

  if (cantidad != null && rendimiento != null && rendimiento > 0) {
    if (rendimientoTiempoBase === "POR_MINUTO") {
      return Math.max(1, Math.round(cantidad / rendimiento));
    }
    // POR_HORA
    const horas = cantidad / rendimiento;
    return Math.max(1, Math.round(horas * 60));
  }

  return null;
}
