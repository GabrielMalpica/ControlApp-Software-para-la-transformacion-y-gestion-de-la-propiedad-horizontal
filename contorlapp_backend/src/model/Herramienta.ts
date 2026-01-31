import { z } from "zod";

export const ModoControlHerramientaZ = z.enum([
  "PRESTAMO",
  "CONSUMO",
  "VIDA_CORTA",
]);
export const EstadoSolicitudZ = z.enum(["PENDIENTE", "APROBADA", "RECHAZADA"]);

// ✅ si tu stock maneja estado
export const EstadoHerramientaStockZ = z.enum([
  "OPERATIVA",
  "DANADA",
  "PERDIDA",
  "BAJA",
]);

export const HerramientaIdParam = z.object({
  herramientaId: z.coerce.number().int().positive(),
});

export const ConjuntoNitParam = z.object({
  nit: z.string().min(3),
});

export const CrearHerramientaBody = z.object({
  empresaId: z.string().min(3),
  nombre: z.string().min(2).max(120),
  unidad: z.string().min(1).max(30).default("UNIDAD"),
  modoControl: ModoControlHerramientaZ.default("PRESTAMO"),
  vidaUtilDias: z.coerce.number().int().positive().optional().nullable(),
  umbralBajo: z.coerce.number().int().min(0).optional().nullable(),
});

export const EditarHerramientaBody = z.object({
  nombre: z.string().min(2).max(120).optional(),
  unidad: z.string().min(1).max(30).optional(),
  modoControl: ModoControlHerramientaZ.optional(),
  vidaUtilDias: z.coerce.number().int().positive().optional().nullable(),
  umbralBajo: z.coerce.number().int().min(0).optional().nullable(),
});

export const ListarHerramientasQuery = z.object({
  empresaId: z.string().min(3),
  nombre: z.string().optional(),
  take: z.coerce.number().int().min(1).max(100).default(50),
  skip: z.coerce.number().int().min(0).default(0),
});

// -------- STOCK (por conjunto) --------

export const UpsertStockBody = z.object({
  herramientaId: z.coerce.number().int().positive(),
  cantidad: z.coerce.number().min(0),
  // si tu modelo tiene estado en el unique, lo mandas o lo default-eas:
  estado: EstadoHerramientaStockZ.optional().default("OPERATIVA"),
});

export const AjustarStockBody = z.object({
  delta: z.coerce.number(),
  estado: EstadoHerramientaStockZ.optional().default("OPERATIVA"),
});

// -------- SOLICITUDES --------

export const CrearSolicitudHerramientaBody = z.object({
  conjuntoId: z.string().min(3),
  empresaId: z.string().min(3).optional().nullable(),
  items: z
    .array(
      z.object({
        herramientaId: z.coerce.number().int().positive(),
        cantidad: z.coerce.number().positive(),
      })
    )
    .min(1),
});

export const CambiarEstadoSolicitudBody = z.object({
  estado: EstadoSolicitudZ,
  observacionRespuesta: z.string().max(500).optional().nullable(),
});
