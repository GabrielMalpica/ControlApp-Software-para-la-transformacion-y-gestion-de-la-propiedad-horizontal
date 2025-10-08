// src/models/tarea.ts
import { z } from "zod";
import { EstadoTarea } from "../generated/prisma";

/** Items de insumos usados (se guardarán en el JSON `insumosUsados`) */
export const InsumoUsadoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

/** Crear tarea dentro de un conjunto (opcional) y ubicación/elemento obligatorios */
export const CrearTareaDTO = z.object({
  descripcion: z.string().min(3),
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
  duracionHoras: z.number().int().positive(),
  operarioId: z.number().int().positive(),
  ubicacionId: z.number().int().positive(),
  elementoId: z.number().int().positive(),
  conjuntoId: z.string().min(3).optional(),     // nit (opcional según Prisma)
  supervisorId: z.number().int().optional(),    // puede ser null en Prisma
  evidencias: z.array(z.string().url()).optional().default([]),
  insumosUsados: z.array(InsumoUsadoItemDTO).optional().default([]),
});

/** Editar tarea (parcial) */
export const EditarTareaDTO = z.object({
  descripcion: z.string().min(3).optional(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionHoras: z.number().int().positive().optional(),
  operarioId: z.number().int().positive().optional(),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  conjuntoId: z.string().min(3).optional().nullable(),
  supervisorId: z.number().int().optional().nullable(),
  estado: z.nativeEnum(EstadoTarea).optional(),
  evidencias: z.array(z.string()).optional(), // URLs o rutas ya validadas arriba si quieres
  insumosUsados: z.array(InsumoUsadoItemDTO).optional(),
  observacionesRechazo: z.string().optional().nullable(),
});

/** Filtros para listar/consultar tareas */
export const FiltroTareaDTO = z.object({
  conjuntoId: z.string().optional(),
  operarioId: z.number().int().optional(),
  supervisorId: z.number().int().optional(),
  ubicacionId: z.number().int().optional(),
  elementoId: z.number().int().optional(),
  estado: z.nativeEnum(EstadoTarea).optional(),
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
  evidencias: z.array(z.string()).min(1), // URLs/rutas
});

/** Registrar insumos usados */
export const RegistrarInsumosUsadosDTO = z.object({
  insumosUsados: z.array(InsumoUsadoItemDTO).min(1),
});
