// src/models/solicitudTarea.ts
import { z } from "zod";
import { EstadoSolicitud } from "@prisma/client";

/** Crear solicitud de tarea asociada a conjunto/ubicación/elemento */
export const CrearSolicitudTareaDTO = z.object({
  descripcion: z.string().min(3),
  duracionHoras: z.number().int().positive(),
  conjuntoId: z.string().min(3),
  ubicacionId: z.number().int().positive(),
  elementoId: z.number().int().positive(),
  empresaId: z.string().min(3).optional(),
  observaciones: z.string().optional(),
});

/** Editar solicitud de tarea */
export const EditarSolicitudTareaDTO = z.object({
  descripcion: z.string().min(3).optional(),
  duracionHoras: z.number().int().positive().optional(),
  empresaId: z.string().min(3).optional().nullable(),
  observaciones: z.string().optional().nullable(),
  estado: z.nativeEnum(EstadoSolicitud).optional(), // si permites cambio directo
});

/** Aprobar solicitud de tarea */
export const AprobarSolicitudTareaDTO = z.object({
  // si deseas registrar quién aprueba, lo puedes extender
});

/** Rechazar solicitud de tarea */
export const RechazarSolicitudTareaDTO = z.object({
  observaciones: z.string().min(3).optional(),
});

/** Filtros */
export const FiltroSolicitudTareaDTO = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  estado: z.nativeEnum(EstadoSolicitud).optional(),
});
