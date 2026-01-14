import { z } from "zod";

/** Crear solicitud de maquinaria */
export const CrearSolicitudMaquinariaDTO = z.object({
  conjuntoId: z.string().min(3), // nit
  maquinariaId: z.number().int().positive(),
  operarioId: z.string().min(1), // ✅ Operario.id es String
  empresaId: z.string().min(3).optional(),
  fechaUso: z.coerce.date(),
  fechaDevolucionEstimada: z.coerce.date(),
});

/** Editar solicitud de maquinaria */
export const EditarSolicitudMaquinariaDTO = z.object({
  maquinariaId: z.number().int().positive().optional(),
  operarioId: z.string().min(1).optional(), // ✅
  empresaId: z.string().min(3).optional().nullable(),
  fechaUso: z.coerce.date().optional(),
  fechaDevolucionEstimada: z.coerce.date().optional(),
});

/** Aprobar solicitud de maquinaria */
export const AprobarSolicitudMaquinariaDTO = z.object({
  fechaAprobacion: z.coerce.date().optional(),
});

/** Filtros de consulta */
export const FiltroSolicitudMaquinariaDTO = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  maquinariaId: z.number().int().optional(),
  operarioId: z.string().optional(), // ✅
  aprobado: z.boolean().optional(), // ✅ déjalo SOLO si existe en tu schema
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});
