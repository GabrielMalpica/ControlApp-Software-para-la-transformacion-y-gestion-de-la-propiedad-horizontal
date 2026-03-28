"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FiltroSolicitudHerramientaDTO = exports.AprobarSolicitudHerramientaDTO = exports.CrearSolicitudHerramientaDTO = void 0;
const zod_1 = require("zod");
exports.CrearSolicitudHerramientaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    items: zod_1.z
        .array(zod_1.z.object({
        herramientaId: zod_1.z.coerce.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive(),
        // opcional: si quieres permitir pedir estado distinto, lo normal es OPERATIVA
        estado: zod_1.z
            .enum(["OPERATIVA", "DANADA", "PERDIDA", "BAJA"])
            .optional()
            .default("OPERATIVA"),
    }))
        .min(1),
});
exports.AprobarSolicitudHerramientaDTO = zod_1.z.object({
    fechaAprobacion: zod_1.z.coerce.date().optional(),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    fechaDevolucionEstimada: zod_1.z.coerce.date().optional().nullable(),
    // opcional: si quieres que el gerente decida a qué estado entra el stock aprobado
    estadoIngreso: zod_1.z
        .enum(["OPERATIVA", "DANADA", "PERDIDA", "BAJA"])
        .optional()
        .default("OPERATIVA"),
});
exports.FiltroSolicitudHerramientaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3).optional(),
    empresaId: zod_1.z.string().min(3).optional(),
    estado: zod_1.z.enum(["PENDIENTE", "APROBADA", "RECHAZADA"]).optional(),
    fechaDesde: zod_1.z.coerce.date().optional(),
    fechaHasta: zod_1.z.coerce.date().optional(),
});
