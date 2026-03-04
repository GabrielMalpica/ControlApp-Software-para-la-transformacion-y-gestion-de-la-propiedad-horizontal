"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FiltroSolicitudInsumoDTO = exports.AprobarSolicitudInsumoDTO = exports.CrearSolicitudInsumoDTO = exports.SolicitudInsumoItemDTO = void 0;
// src/models/solicitudInsumo.ts
const zod_1 = require("zod");
/** Ítem de la solicitud (tabla SolicitudInsumoItem) */
exports.SolicitudInsumoItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
/** Crear solicitud de insumos para un conjunto (empresa opcional) */
exports.CrearSolicitudInsumoDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3), // nit
    empresaId: zod_1.z.string().min(3).optional(),
    items: zod_1.z.array(exports.SolicitudInsumoItemDTO).min(1),
});
/** Aprobar solicitud de insumos */
exports.AprobarSolicitudInsumoDTO = zod_1.z.object({
    empresaId: zod_1.z.string().min(3).optional(), // si quieres registrar la empresa que aprueba
    fechaAprobacion: zod_1.z.coerce.date().optional(), // default en service: new Date()
});
/** Filtros de consulta */
exports.FiltroSolicitudInsumoDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    empresaId: zod_1.z.string().optional(),
    aprobado: zod_1.z.boolean().optional(),
    fechaDesde: zod_1.z.coerce.date().optional(),
    fechaHasta: zod_1.z.coerce.date().optional(),
});
