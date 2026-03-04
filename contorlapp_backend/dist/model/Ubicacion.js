"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ubicacionPublicSelect = exports.FiltroUbicacionDTO = exports.EditarUbicacionDTO = exports.CrearUbicacionDTO = void 0;
exports.toUbicacionPublica = toUbicacionPublica;
// src/models/ubicacion.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/** Crear ubicación dentro de un conjunto */
exports.CrearUbicacionDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2),
    conjuntoId: zod_1.z.string().min(3),
});
/** Editar ubicación (solo nombre por ahora) */
exports.EditarUbicacionDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2).optional(),
});
/** Filtro de búsqueda de ubicaciones */
exports.FiltroUbicacionDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3).optional(),
    nombre: zod_1.z.string().optional(),
});
/* ===================== SELECT BASE ===================== */
exports.ubicacionPublicSelect = {
    id: true,
    nombre: true,
    conjuntoId: true,
};
/** Helper para castear select a tipo público */
function toUbicacionPublica(row) {
    return row;
}
