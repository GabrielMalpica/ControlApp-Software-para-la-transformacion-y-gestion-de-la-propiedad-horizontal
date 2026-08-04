// src/model/DefinicionTareaPreventiva.ts
import { z } from "zod";
import {
  DiaSemana,
  Frecuencia,
  TipoMaquinaria,
  UnidadCalculo,
} from "@prisma/client";

const UsuarioIdDTO = z
  .union([z.string().trim().min(1), z.number().int().positive()])
  .transform((value) => String(value));

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
  fechasProgramadasJson?: string[] | null;

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
        tipo: TipoMaquinaria;
        cantidad: number;
        maquinariaSugeridaId?: number | null;
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

/**
 * La definicion preventiva declara la NECESIDAD de maquinaria (que tipo y cuantas),
 * no una maquina concreta. La maquina real se asigna despues desde el cronograma
 * de maquinaria. `maquinariaId` se sigue aceptando de entrada como sugerencia,
 * para no romper clientes antiguos.
 */
/**
 * `nullish` en los ids no es cosmético: el controller parsea el DTO y el servicio
 * lo vuelve a parsear, así que el esquema tiene que aceptar su propia salida
 * (donde `maquinariaSugeridaId` ya es `null`).
 */
const MaquinariaPlanItemDTO = z
  .object({
    tipo: z.nativeEnum(TipoMaquinaria),
    cantidad: z.coerce.number().int().min(1).default(1),
    maquinariaSugeridaId: z.number().int().positive().nullish(),
    maquinariaId: z.number().int().positive().nullish(),
  })
  .transform(({ tipo, cantidad, maquinariaSugeridaId, maquinariaId }) => ({
    tipo,
    cantidad,
    maquinariaSugeridaId: maquinariaSugeridaId ?? maquinariaId ?? null,
  }));

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
    fechasProgramadasJson: z.array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)).optional(),

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

    responsableSugeridoId: UsuarioIdDTO.optional(),
    operariosIds: z.array(UsuarioIdDTO).optional(),

    supervisorId: UsuarioIdDTO.optional(),

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
  fechasProgramadasJson: z
    .array(z.string().regex(/^\d{4}-\d{2}-\d{2}$/))
    .optional()
    .nullable(),

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

  responsableSugeridoId: UsuarioIdDTO.optional().nullable(),
  operariosIds: z.array(UsuarioIdDTO).optional().nullable(),

  supervisorId: UsuarioIdDTO.optional().nullable(),
  activo: z.boolean().optional(),
});

/** Borrado en lote de definiciones preventivas */
export const EliminarPreventivasLoteDTO = z.object({
  ids: z.array(z.number().int().positive()).min(1).max(200),
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
const ConfirmacionReemplazoDTO = z.object({
  defId: z.number().int().positive(),
  fecha: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  prioridadSolicitante: z.number().int().min(1).max(3),
  prioridadObjetivo: z.number().int().min(2).max(3),
  aceptar: z.boolean(),
  candidataId: z.number().int().positive().optional(),
});

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
  confirmacionesReemplazo: z.array(ConfirmacionReemplazoDTO).optional(),
  /**
   * RESET  = se descarta el borrador previo y se planifica todo de cero (default, contrato antiguo).
   * CONSERVAR = se respeta el borrador ya cuadrado y solo se planifican las
   *             definiciones que aun no tienen tarea en el periodo.
   */
  modo: z.enum(["RESET", "CONSERVAR"]).optional().default("RESET"),
});

export const PeriodoBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
});

export const ListarExcluidasBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
  fecha: z.coerce.date().optional(),
});

export const SugerirHuecosExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.coerce.number().int().positive(),
  fechaPreferida: z.coerce.date().optional(),
  maxOpciones: z.coerce.number().int().min(1).max(20).optional(),
});

export const AgendarExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.coerce.number().int().positive(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  bloques: z
    .array(
      z.object({
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      }),
    )
    .min(1)
    .optional(),
}).refine(
  (d) =>
    ((d.fechaInicio == null && d.fechaFin == null) ||
      (d.fechaInicio != null && d.fechaFin != null && d.fechaFin >= d.fechaInicio)) &&
    (d.bloques == null || d.bloques.every((b) => b.fechaFin >= b.fechaInicio)) &&
    !(
      d.bloques != null &&
      d.bloques.length > 0 &&
      (d.fechaInicio != null || d.fechaFin != null)
    ),
  {
    message:
      "Envia fechaInicio/fechaFin o bloques validos, pero no ambos a la vez.",
  },
);

export const ReemplazarConExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.coerce.number().int().positive(),
  excluidaId: z.coerce.number().int().positive(),
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
  fechasProgramadasJson: true,

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
