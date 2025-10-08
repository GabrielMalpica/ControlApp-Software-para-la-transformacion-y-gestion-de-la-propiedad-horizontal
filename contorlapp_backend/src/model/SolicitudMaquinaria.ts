import { z } from "zod";

/** Crear solicitud de maquinaria */
export const CrearSolicitudMaquinariaDTO = z.object({
  conjuntoId: z.string().min(3),       // nit
  maquinariaId: z.number().int().positive(),
  operarioId: z.number().int().positive(), // responsable
  empresaId: z.string().min(3).optional(),
  fechaUso: z.coerce.date(),
  fechaDevolucionEstimada: z.coerce.date(),
});

/** Editar solicitud de maquinaria */
export const EditarSolicitudMaquinariaDTO = z.object({
  maquinariaId: z.number().int().positive().optional(),
  operarioId: z.number().int().positive().optional(),
  empresaId: z.string().min(3).optional().nullable(),
  fechaUso: z.coerce.date().optional(),
  fechaDevolucionEstimada: z.coerce.date().optional(),
});

/** Aprobar solicitud de maquinaria */
export const AprobarSolicitudMaquinariaDTO = z.object({
  fechaAprobacion: z.coerce.date().optional(), // default en service: new Date()
});

/** Filtros de consulta */
export const FiltroSolicitudMaquinariaDTO = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  maquinariaId: z.number().int().optional(),
  operarioId: z.number().int().optional(),
  aprobado: z.boolean().optional(),
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});
