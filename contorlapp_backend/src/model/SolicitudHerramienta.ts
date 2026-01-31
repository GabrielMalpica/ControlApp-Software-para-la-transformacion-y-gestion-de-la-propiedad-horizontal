import { z } from "zod";

export const CrearSolicitudHerramientaDTO = z.object({
  conjuntoId: z.string().min(3),
  empresaId: z.string().min(3).optional().nullable(),
  items: z
    .array(
      z.object({
        herramientaId: z.coerce.number().int().positive(),
        cantidad: z.coerce.number().positive(),
        // opcional: si quieres permitir pedir estado distinto, lo normal es OPERATIVA
        estado: z
          .enum(["OPERATIVA", "DANADA", "PERDIDA", "BAJA"])
          .optional()
          .default("OPERATIVA"),
      })
    )
    .min(1),
});

export const AprobarSolicitudHerramientaDTO = z.object({
  fechaAprobacion: z.coerce.date().optional(),
  empresaId: z.string().min(3).optional().nullable(),
  // opcional: si quieres que el gerente decida a qué estado entra el stock aprobado
  estadoIngreso: z
    .enum(["OPERATIVA", "DANADA", "PERDIDA", "BAJA"])
    .optional()
    .default("OPERATIVA"),
});

export const FiltroSolicitudHerramientaDTO = z.object({
  conjuntoId: z.string().min(3).optional(),
  empresaId: z.string().min(3).optional(),
  estado: z.enum(["PENDIENTE", "APROBADA", "RECHAZADA"]).optional(),
  fechaDesde: z.coerce.date().optional(),
  fechaHasta: z.coerce.date().optional(),
});
