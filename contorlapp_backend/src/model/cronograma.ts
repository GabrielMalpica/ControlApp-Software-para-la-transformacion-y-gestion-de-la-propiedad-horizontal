// src/models/cronograma.ts
import { z } from "zod";

/**
 * DTO para crear o actualizar un cronograma.
 * Se asume que `conjuntoId` (nit) existe y las tareas
 * se crearán o actualizarán dentro de ese conjunto.
 */
export const CrearCronogramaDTO = z.object({
  conjuntoId: z.string().min(3), // nit del conjunto
  tareas: z.array(
    z.object({
      descripcion: z.string().min(3),
      fechaInicio: z.coerce.date(),
      fechaFin: z.coerce.date(),
      duracionHoras: z.number().int().positive(),
      ubicacionId: z.number().int(),
      elementoId: z.number().int(),
      operarioId: z.number().int(),
      supervisorId: z.number().int().optional(),
      observaciones: z.string().optional(),
    })
  ).min(1),
});

/**
 * DTO para actualizar tareas dentro de un cronograma existente.
 * Por ejemplo, para cambiar fechas, duraciones o asignaciones.
 */
export const EditarCronogramaDTO = z.object({
  tareas: z.array(
    z.object({
      id: z.number().int().positive(),
      descripcion: z.string().min(3).optional(),
      fechaInicio: z.coerce.date().optional(),
      fechaFin: z.coerce.date().optional(),
      duracionHoras: z.number().int().positive().optional(),
      estado: z.string().optional(), // podría validarse con enum EstadoTarea
      observaciones: z.string().optional().nullable(),
    })
  ).min(1),
});

/**
 * DTO para filtrar o consultar el cronograma.
 * Útil para endpoints tipo: /cronograma?fechaInicio=&fechaFin=
 */
export const FiltroCronogramaDTO = z.object({
  conjuntoId: z.string().min(3), // nit del conjunto
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  estado: z.string().optional(), // opcionalmente filtrar por EstadoTarea
});
