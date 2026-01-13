// src/models/tarea.ts
import { z } from "zod";
import { EstadoTarea, TipoTarea, Frecuencia } from "../generated/prisma";

export const InsumoUsadoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

/** Planificación (JSON) */
export const InsumoPlanItemDTO = z.object({
  insumoId: z.number().int().positive(),
  consumoPorUnidad: z.coerce.number().min(0),
});
export const MaquinariaPlanItemDTO = z.object({
  maquinariaId: z.number().int().positive().optional(),
  tipo: z.string().min(1).optional(),
  cantidad: z.coerce.number().min(0).optional(),
});

/** Crear tarea (correctiva o preventiva ya instanciada) */
export const CrearTareaDTO = z
  .object({
    descripcion: z.string().min(3),

    fechaInicio: z.coerce.date(),
    fechaFin: z.coerce.date(),

    duracionMinutos: z.number().int().min(1),

    duracionHoras: z.coerce.number().positive().optional(),

    prioridad: z.number().int().min(1).max(3).optional(),

    tipo: z.nativeEnum(TipoTarea).optional(),
    estado: z.nativeEnum(EstadoTarea).optional(),
    frecuencia: z.nativeEnum(Frecuencia).optional(),

    evidencias: z.array(z.string()).optional().default([]),
    insumosUsados: z.any().optional(),

    observaciones: z.string().optional(),
    observacionesRechazo: z.string().optional(),

    ubicacionId: z.number().int().positive(),
    elementoId: z.number().int().positive(),

    conjuntoId: z.string().min(1).nullable().optional(),
    supervisorId: z.number().int().positive().nullable().optional(),

    operariosIds: z.array(z.number().int().positive()).optional(),
    operarioId: z.number().int().positive().optional(),
  })
  .refine(
    (d) => {
      const okDur = d.duracionMinutos != null || d.duracionHoras != null;
      if (!okDur) return false;

      if (d.duracionMinutos != null) return d.duracionMinutos >= 1;

      return (d.duracionHoras ?? 0) > 0;
    },
    { message: "Debe indicar duracionMinutos o duracionHoras (>0)." }
  );

/** Editar tarea (parcial) */
export const EditarTareaDTO = z.object({
  descripcion: z.string().min(3).optional(),

  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),

  duracionMinutos: z.number().int().min(1).optional(),
  duracionHoras: z.coerce.number().positive().optional(),

  prioridad: z.number().int().min(1).max(3).optional(),

  tipo: z.nativeEnum(TipoTarea).optional(),
  estado: z.nativeEnum(EstadoTarea).optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional(),

  evidencias: z.array(z.string()).optional(),
  insumosUsados: z.any().optional(),

  observaciones: z.string().nullable().optional(),
  observacionesRechazo: z.string().nullable().optional(),

  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),

  conjuntoId: z.string().min(1).nullable().optional(),
  supervisorId: z.number().int().positive().nullable().optional(),

  operariosIds: z.array(z.number().int().positive()).optional(),
  operarioId: z.number().int().positive().optional(),
});

/** Filtros para listar/consultar tareas */
export const FiltroTareaDTO = z.object({
  conjuntoId: z.string().optional(),
  operarioId: z.number().int().optional(),
  supervisorId: z.number().int().optional(),
  ubicacionId: z.number().int().optional(),
  elementoId: z.number().int().optional(),

  tipo: z.nativeEnum(TipoTarea).optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional(),
  estado: z.nativeEnum(EstadoTarea).optional(),
  borrador: z.boolean().optional(),

  periodoAnio: z.number().int().optional(),
  periodoMes: z.number().int().min(1).max(12).optional(),

  grupoPlanId: z.string().uuid().optional(),

  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
});

/** Iniciar tarea (track operario y timestamp real) */
export const IniciarTareaDTO = z.object({
  fechaIniciarTarea: z.coerce.date().default(() => new Date()),
});

/** Finalizar tarea (track operario y timestamp real) */
export const FinalizarTareaDTO = z.object({
  fechaFinalizarTarea: z.coerce.date().default(() => new Date()),
});

/** Verificar tarea por supervisor/empresa */
export const VerificarTareaDTO = z.object({
  supervisorId: z.number().int().optional(), // si aplica verificación por supervisor
  fechaVerificacion: z.coerce.date().default(() => new Date()),
});

/** Aprobar tarea por empresa (usa relación empresaAprobada) */
export const AprobarTareaEmpresaDTO = z.object({
  empresaAprobadaId: z.number().int().positive(),
});

/** Rechazar tarea por empresa (usa relación empresaRechazada) */
export const RechazarTareaEmpresaDTO = z.object({
  empresaRechazadaId: z.number().int().positive(),
  observacionesRechazo: z.string().min(3).optional(),
});

/** Agregar evidencias (anexos) */
export const AgregarEvidenciasDTO = z.object({
  evidencias: z.array(z.string()).min(1),
});

/** Registrar insumos usados (JSON real) */
export const RegistrarInsumosUsadosDTO = z.object({
  insumosUsados: z.array(InsumoUsadoItemDTO).min(1),
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const tareaPublicSelect = {
  id: true,
  descripcion: true,
  fechaInicio: true,
  fechaFin: true,

  duracionMinutos: true,
  prioridad: true,

  estado: true,
  evidencias: true,
  insumosUsados: true,
  observaciones: true,
  observacionesRechazo: true,
  tipo: true,
  frecuencia: true,
  conjuntoId: true,
  supervisorId: true,
  ubicacionId: true,
  elementoId: true,
} as const;

/** Helper para castear el resultado Prisma */
export type TareaPublica = {
  [K in keyof typeof tareaPublicSelect]: any;
};
export function toTareaPublica<
  T extends Record<keyof typeof tareaPublicSelect, any>
>(row: T): TareaPublica {
  return row as unknown as TareaPublica;
}
