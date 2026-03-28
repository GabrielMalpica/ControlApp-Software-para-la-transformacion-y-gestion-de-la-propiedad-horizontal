"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CambiarEstadoSolicitudBody = exports.CrearSolicitudHerramientaBody = exports.EmpresaNitParam = exports.DevolverPrestamoHerramientaBody = exports.AjustarStockBody = exports.UpsertStockBody = exports.ListarHerramientasQuery = exports.EditarHerramientaBody = exports.CrearHerramientaBody = exports.ConjuntoNitParam = exports.HerramientaIdParam = exports.EstadoHerramientaStockZ = exports.EstadoSolicitudZ = exports.CategoriaHerramientaZ = exports.ModoControlHerramientaZ = void 0;
const zod_1 = require("zod");
exports.ModoControlHerramientaZ = zod_1.z.enum([
    "PRESTAMO",
    "CONSUMO",
    "VIDA_CORTA",
]);
exports.CategoriaHerramientaZ = zod_1.z.enum([
    "LIMPIEZA",
    "JARDINERIA",
    "PISCINA",
    "OTROS",
]);
exports.EstadoSolicitudZ = zod_1.z.enum(["PENDIENTE", "APROBADA", "RECHAZADA"]);
// ✅ si tu stock maneja estado
exports.EstadoHerramientaStockZ = zod_1.z.enum([
    "OPERATIVA",
    "DANADA",
    "PERDIDA",
    "BAJA",
]);
exports.HerramientaIdParam = zod_1.z.object({
    herramientaId: zod_1.z.coerce.number().int().positive(),
});
exports.ConjuntoNitParam = zod_1.z.object({
    nit: zod_1.z.string().min(3),
});
exports.CrearHerramientaBody = zod_1.z.object({
    empresaId: zod_1.z.string().min(3),
    nombre: zod_1.z.string().min(2).max(120),
    unidad: zod_1.z.string().min(1).max(30).default("UNIDAD"),
    categoria: exports.CategoriaHerramientaZ.default("OTROS"),
    modoControl: exports.ModoControlHerramientaZ.default("PRESTAMO"),
    vidaUtilDias: zod_1.z.coerce.number().int().positive().optional().nullable(),
    umbralBajo: zod_1.z.coerce.number().int().min(0).optional().nullable(),
});
exports.EditarHerramientaBody = zod_1.z.object({
    nombre: zod_1.z.string().min(2).max(120).optional(),
    unidad: zod_1.z.string().min(1).max(30).optional(),
    categoria: exports.CategoriaHerramientaZ.optional(),
    modoControl: exports.ModoControlHerramientaZ.optional(),
    vidaUtilDias: zod_1.z.coerce.number().int().positive().optional().nullable(),
    umbralBajo: zod_1.z.coerce.number().int().min(0).optional().nullable(),
});
exports.ListarHerramientasQuery = zod_1.z.object({
    empresaId: zod_1.z.string().min(3),
    nombre: zod_1.z.string().optional(),
    take: zod_1.z.coerce.number().int().min(1).max(100).default(50),
    skip: zod_1.z.coerce.number().int().min(0).default(0),
});
// -------- STOCK (por conjunto) --------
exports.UpsertStockBody = zod_1.z.object({
    herramientaId: zod_1.z.coerce.number().int().positive(),
    cantidad: zod_1.z.coerce.number().min(0),
    // si tu modelo tiene estado en el unique, lo mandas o lo default-eas:
    estado: exports.EstadoHerramientaStockZ.optional().default("OPERATIVA"),
});
exports.AjustarStockBody = zod_1.z.object({
    delta: zod_1.z.coerce.number(),
    estado: exports.EstadoHerramientaStockZ.optional().default("OPERATIVA"),
});
exports.DevolverPrestamoHerramientaBody = zod_1.z.object({
    cantidad: zod_1.z.coerce.number().positive(),
    estado: exports.EstadoHerramientaStockZ.optional().default("OPERATIVA"),
});
exports.EmpresaNitParam = zod_1.z.object({
    empresaId: zod_1.z.string().min(3),
});
// -------- SOLICITUDES --------
exports.CrearSolicitudHerramientaBody = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    items: zod_1.z
        .array(zod_1.z.object({
        herramientaId: zod_1.z.coerce.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive(),
    }))
        .min(1),
});
exports.CambiarEstadoSolicitudBody = zod_1.z.object({
    estado: exports.EstadoSolicitudZ,
    observacionRespuesta: zod_1.z.string().max(500).optional().nullable(),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    fechaDevolucionEstimada: zod_1.z.coerce.date().optional().nullable(),
    estadoIngreso: exports.EstadoHerramientaStockZ.optional(),
});
