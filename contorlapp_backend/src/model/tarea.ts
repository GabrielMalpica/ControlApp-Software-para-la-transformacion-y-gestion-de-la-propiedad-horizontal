// src/models/tarea.ts
import { z } from "zod";
import { EstadoTarea, TipoTarea, Frecuencia } from "../generated/prisma";

/** Items de insumos usados (se guardarán en el JSON `insumosUsados`) */
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
export const CrearTareaDTO = z.object({
  descripcion: z.string().min(3),

  // ventana de tiempo y duración en horas (enteras)
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
  duracionHoras: z.number().int().positive(),

  // asignaciones (opcionales según Prisma)
  operarioId: z.number().int().positive().optional(),
  supervisorId: z.number().int().positive().optional(),
  ubicacionId: z.number().int().positive(),
  elementoId: z.number().int().positive(),
  conjuntoId: z.string().min(3).optional(), // nit

  // tipo/frecuencia
  tipo: z.nativeEnum(TipoTarea).default("CORRECTIVA"),
  frecuencia: z.nativeEnum(Frecuencia).optional(),

  // estado inicial y flags de borrador
  estado: z.nativeEnum(EstadoTarea).default("ASIGNADA"),
  borrador: z.boolean().default(false),
  periodoAnio: z.number().int().optional(),
  periodoMes: z.number().int().min(1).max(12).optional(),

  // agrupación de bloques
  grupoPlanId: z.string().uuid().optional(),
  bloqueIndex: z.number().int().positive().optional(),
  bloquesTotales: z.number().int().positive().optional(),

  // evidencia/consumos reales
  evidencias: z.array(z.string()).optional().default([]),
  insumosUsados: z.array(InsumoUsadoItemDTO).optional().default([]),

  // planificación/estimaciones (Decimal en Prisma -> number aquí)
  tiempoEstimadoHoras: z.coerce.number().min(0).optional(),
  insumoPrincipalId: z.number().int().positive().optional(),
  consumoPrincipalPorUnidad: z.coerce.number().min(0).optional(),
  consumoTotalEstimado: z.coerce.number().min(0).optional(),
  insumosPlanJson: z.array(InsumoPlanItemDTO).optional(),
  maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional(),

  observaciones: z.string().optional(),
});

/** Editar tarea (parcial) */
export const EditarTareaDTO = z.object({
  descripcion: z.string().min(3).optional(),

  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionHoras: z.number().int().positive().optional(),

  operarioId: z.number().int().positive().optional().nullable(),
  supervisorId: z.number().int().positive().optional().nullable(),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  conjuntoId: z.string().min(3).optional().nullable(),

  tipo: z.nativeEnum(TipoTarea).optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional().nullable(),

  estado: z.nativeEnum(EstadoTarea).optional(),
  borrador: z.boolean().optional(),
  periodoAnio: z.number().int().optional().nullable(),
  periodoMes: z.number().int().min(1).max(12).optional().nullable(),

  grupoPlanId: z.string().uuid().optional().nullable(),
  bloqueIndex: z.number().int().positive().optional().nullable(),
  bloquesTotales: z.number().int().positive().optional().nullable(),

  evidencias: z.array(z.string()).optional(),
  insumosUsados: z.array(InsumoUsadoItemDTO).optional(),
  observaciones: z.string().optional().nullable(),
  observacionesRechazo: z.string().optional().nullable(),

  tiempoEstimadoHoras: z.coerce.number().min(0).optional().nullable(),
  insumoPrincipalId: z.number().int().positive().optional().nullable(),
  consumoPrincipalPorUnidad: z.coerce.number().min(0).optional().nullable(),
  consumoTotalEstimado: z.coerce.number().min(0).optional().nullable(),
  insumosPlanJson: z.array(InsumoPlanItemDTO).optional().nullable(),
  maquinariaPlanJson: z.array(MaquinariaPlanItemDTO).optional().nullable(),
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
  fechaIniciarTarea: true,
  fechaFinalizarTarea: true,
  duracionHoras: true,

  estado: true,
  evidencias: true,
  insumosUsados: true,
  observaciones: true,
  observacionesRechazo: true,
  fechaVerificacion: true,

  operarioId: true,
  supervisorId: true,
  ubicacionId: true,
  elementoId: true,
  conjuntoId: true,

  tipo: true,
  frecuencia: true,

  borrador: true,
  periodoAnio: true,
  periodoMes: true,
  grupoPlanId: true,
  bloqueIndex: true,
  bloquesTotales: true,

  tiempoEstimadoHoras: true,
  insumoPrincipalId: true,
  consumoPrincipalPorUnidad: true,
  consumoTotalEstimado: true,
  insumosPlanJson: true,
  maquinariaPlanJson: true,
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
