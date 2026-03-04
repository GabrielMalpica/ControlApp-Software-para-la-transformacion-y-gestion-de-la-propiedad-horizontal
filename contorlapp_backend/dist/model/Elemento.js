"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.elementoPublicSelect = exports.FiltroElementoDTO = exports.EditarElementoDTO = exports.CrearElementoDTO = void 0;
exports.toElementoPublico = toElementoPublico;
// src/models/elemento.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/** Crear elemento dentro de una ubicación */
exports.CrearElementoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2),
    ubicacionId: zod_1.z.number().int().positive(),
});
/** Editar elemento (solo nombre por ahora) */
exports.EditarElementoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2).optional(),
});
/** Filtro de búsqueda de elementos */
exports.FiltroElementoDTO = zod_1.z.object({
    ubicacionId: zod_1.z.number().int().optional(),
    nombre: zod_1.z.string().optional(),
});
/* ===================== SELECT BASE ===================== */
exports.elementoPublicSelect = {
    id: true,
    nombre: true,
    ubicacionId: true,
};
/** Helper para castear select a tipo público */
function toElementoPublico(row) {
    return row;
}
