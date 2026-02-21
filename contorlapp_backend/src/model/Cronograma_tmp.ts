// src/models/cronograma.ts
import { z } from "zod";
import { EstadoTarea, TipoTarea, Frecuencia } from "../generated/prisma";

/**
 * DTO para crear/actualizar un cronograma (lote de tareas) dentro de un conjunto.
 * Puedes usarlo para crear el borrador mensual o para cargar correctivas.
 */
export const CrearCronogramaDTO = z.object({
  conjuntoId: z.string().min(3), // NIT del conjunto

  // opcional: si es un borrador mensual
  borrador: z.boolean().default(true),
  periodoAnio: z.number().int().optional(),
  periodoMes: z.number().int().min(1).max(12).optional(),

  tareas: z.array(
    z.object({
      descripcion: z.string().min(3),

      // ventana y duración
      fechaInicio: z.coerce.date(),
      fechaFin: z.coerce.date(),
      duracionHoras: z.number().int().positive(),

      // asignaciones
      ubicacionId: z.number().int().positive(),
      elementoId: z.number().int().positive(),
      operarioId: z.number().int().positive().optional(),
      supervisorId: z.number().int().positive().optional(),

      // tipo/frecuencia (si es preventiva)
      tipo: z.nativeEnum(TipoTarea).default("CORRECTIVA"),
      frecuencia: z.nativeEnum(Frecuencia).optional(),

      // agrupación por bloques (si fue partida)
      grupoPlanId: z.string().uuid().optional(),
      bloqueIndex: z.number().int().positive().optional(),
      bloquesTotales: z.number().int().positive().optional(),

      // extras
      observaciones: z.string().optional(),
    }).refine((t) => +t.fechaFin > +t.fechaInicio, {
      message: "fechaFin debe ser mayor que fechaInicio",
      path: ["fechaFin"],
    })
  ).min(1),
});

/**
 * DTO para editar tareas dentro de un cronograma (lote partial update).
 * Útil para mover bloques, cambiar duración, estado, etc.
 */
export const EditarCronogramaDTO = z.object({
  tareas: z.array(
    z.object({
      id: z.number().int().positive(),
      descripcion: z.string().min(3).optional(),

      fechaInicio: z.coerce.date().optional(),
      fechaFin: z.coerce.date().optional(),
      duracionHoras: z.number().int().positive().optional(),

      estado: z.nativeEnum(EstadoTarea).optional(),
      observaciones: z.string().optional().nullable(),

      // reasignaciones
      operarioId: z.number().int().positive().optional().nullable(),
      supervisorId: z.number().int().positive().optional().nullable(),
      ubicacionId: z.number().int().positive().optional(),
      elementoId: z.number().int().positive().optional(),

      // tipo/frecuencia (si cambió)
      tipo: z.nativeEnum(TipoTarea).optional(),
      frecuencia: z.nativeEnum(Frecuencia).optional().nullable(),

      // bloques (si cambió la partición)
      grupoPlanId: z.string().uuid().optional().nullable(),
      bloqueIndex: z.number().int().positive().optional().nullable(),
      bloquesTotales: z.number().int().positive().optional().nullable(),
    }).refine((t) => {
      if (!t.fechaInicio || !t.fechaFin) return true;
      return +t.fechaFin > +t.fechaInicio;
    }, {
      message: "fechaFin debe ser mayor que fechaInicio",
      path: ["fechaFin"],
    })
  ).min(1),
});

/**
 * DTO para filtrar/consultar cronograma.
 * Útil para endpoints tipo: /cronograma?conjuntoId=&periodoMes=&periodoAnio=&dia=...
 */
export const FiltroCronogramaDTO = z.object({
  conjuntoId: z.string().min(3),

  // rango temporal
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),

  // o bien por periodo de borrador
  periodoAnio: z.number().int().optional(),
  periodoMes: z.number().int().min(1).max(12).optional(),
  borrador: z.boolean().optional(),

  // filtros adicionales
  estado: z.nativeEnum(EstadoTarea).optional(),
  tipo: z.nativeEnum(TipoTarea).optional(),
  frecuencia: z.nativeEnum(Frecuencia).optional(),
  operarioId: z.number().int().optional(),
  supervisorId: z.number().int().optional(),
  ubicacionId: z.number().int().optional(),
  elementoId: z.number().int().optional(),
})
.refine((f) => {
  // si viene uno de {fechaInicio, fechaFin}, que vengan ambos
  if ((f.fechaInicio && !f.fechaFin) || (!f.fechaInicio && f.fechaFin)) return false;
  return true;
}, {
  message: "Debe enviar ambos: fechaInicio y fechaFin, o ninguno.",
});
