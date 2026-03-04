"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.jefeOperacionesPublicSelect = exports.EditarJefeOperacionesDTO = exports.CrearJefeOperacionesDTO = void 0;
exports.toJefeOperacionesPublico = toJefeOperacionesPublico;
// src/models/jefeOperaciones.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/** Crear jefe de operaciones */
exports.CrearJefeOperacionesDTO = zod_1.z.object({
    Id: zod_1.z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});
/** Editar jefe de operaciones (solo empresa, opcional) */
exports.EditarJefeOperacionesDTO = zod_1.z.object({
    empresaId: zod_1.z.string().min(3).optional(),
});
/* ===================== SELECT BASE ===================== */
exports.jefeOperacionesPublicSelect = {
    id: true,
    empresaId: true,
};
/** Helper para mapear resultado de Prisma */
function toJefeOperacionesPublico(row) {
    return row;
}
