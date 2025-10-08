// src/models/solicitudInsumo.ts
import { z } from "zod";

/** Ítem de la solicitud (tabla SolicitudInsumoItem) */
export const SolicitudInsumoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

/** Crear solicitud de insumos para un conjunto (empresa opcional) */
export const CrearSolicitudInsumoDTO = z.object({
  conjuntoId: z.string().min(3), // nit
  empresaId: z.string().min(3).optional(),
  items: z.array(SolicitudInsumoItemDTO).min(1),
});

/** Aprobar solicitud de insumos */
export const AprobarSolicitudInsumoDTO = z.object({
  empresaId: z.string().min(3).optional(), // si quieres registrar la empresa que aprueba
  fechaAprobacion: z.coerce.date().optional(), // default en service: new Date()
});

/** Filtros de consulta */
export const FiltroSolicitudInsumoDTO = z.object({
  conjuntoId: z.string().optional(),
  empresaId: z.string().optional(),
  aprobado: z.boolean().optional(),
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});
