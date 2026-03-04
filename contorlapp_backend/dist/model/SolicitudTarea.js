"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FiltroSolicitudTareaDTO = exports.RechazarSolicitudTareaDTO = exports.AprobarSolicitudTareaDTO = exports.EditarSolicitudTareaDTO = exports.CrearSolicitudTareaDTO = void 0;
// src/models/solicitudTarea.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/** Crear solicitud de tarea asociada a conjunto/ubicación/elemento */
exports.CrearSolicitudTareaDTO = zod_1.z.object({
    descripcion: zod_1.z.string().min(3),
    duracionHoras: zod_1.z.number().int().positive(),
    conjuntoId: zod_1.z.string().min(3),
    ubicacionId: zod_1.z.number().int().positive(),
    elementoId: zod_1.z.number().int().positive(),
    empresaId: zod_1.z.string().min(3).optional(),
    observaciones: zod_1.z.string().optional(),
});
/** Editar solicitud de tarea */
exports.EditarSolicitudTareaDTO = zod_1.z.object({
    descripcion: zod_1.z.string().min(3).optional(),
    duracionHoras: zod_1.z.number().int().positive().optional(),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    observaciones: zod_1.z.string().optional().nullable(),
    estado: zod_1.z.nativeEnum(client_1.EstadoSolicitud).optional(), // si permites cambio directo
});
/** Aprobar solicitud de tarea */
exports.AprobarSolicitudTareaDTO = zod_1.z.object({
// si deseas registrar quién aprueba, lo puedes extender
});
/** Rechazar solicitud de tarea */
exports.RechazarSolicitudTareaDTO = zod_1.z.object({
    observaciones: zod_1.z.string().min(3).optional(),
});
/** Filtros */
exports.FiltroSolicitudTareaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    empresaId: zod_1.z.string().optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoSolicitud).optional(),
});
