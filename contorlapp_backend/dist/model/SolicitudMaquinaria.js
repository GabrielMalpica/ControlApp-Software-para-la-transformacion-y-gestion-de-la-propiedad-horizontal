"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FiltroSolicitudMaquinariaDTO = exports.AprobarSolicitudMaquinariaDTO = exports.EditarSolicitudMaquinariaDTO = exports.CrearSolicitudMaquinariaDTO = void 0;
const zod_1 = require("zod");
/** Crear solicitud de maquinaria */
exports.CrearSolicitudMaquinariaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3), // nit
    maquinariaId: zod_1.z.number().int().positive(),
    operarioId: zod_1.z.string().min(1), // ✅ Operario.id es String
    empresaId: zod_1.z.string().min(3).optional(),
    fechaUso: zod_1.z.coerce.date(),
    fechaDevolucionEstimada: zod_1.z.coerce.date(),
});
/** Editar solicitud de maquinaria */
exports.EditarSolicitudMaquinariaDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive().optional(),
    operarioId: zod_1.z.string().min(1).optional(), // ✅
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    fechaUso: zod_1.z.coerce.date().optional(),
    fechaDevolucionEstimada: zod_1.z.coerce.date().optional(),
});
/** Aprobar solicitud de maquinaria */
exports.AprobarSolicitudMaquinariaDTO = zod_1.z.object({
    fechaAprobacion: zod_1.z.coerce.date().optional(),
});
/** Filtros de consulta */
exports.FiltroSolicitudMaquinariaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    empresaId: zod_1.z.string().optional(),
    maquinariaId: zod_1.z.number().int().optional(),
    operarioId: zod_1.z.string().optional(), // ✅
    aprobado: zod_1.z.boolean().optional(), // ✅ déjalo SOLO si existe en tu schema
    fechaDesde: zod_1.z.coerce.date().optional(),
    fechaHasta: zod_1.z.coerce.date().optional(),
});
