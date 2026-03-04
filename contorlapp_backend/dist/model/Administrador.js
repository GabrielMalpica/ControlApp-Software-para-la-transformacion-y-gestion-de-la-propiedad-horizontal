"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.administradorPublicSelect = exports.EditarAdministradorDTO = exports.CrearAdministradorDTO = void 0;
exports.toAdministradorPublico = toAdministradorPublico;
// src/models/administrador.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/**
 * DTO para creación del Administrador.
 * Requiere un Usuario ya creado con rol = "administrador".
 */
exports.CrearAdministradorDTO = zod_1.z.object({
    Id: zod_1.z.string().min(1, "El id (cédula) del usuario es obligatorio"),
});
/**
 * DTO para edición — actualmente no hay campos editables,
 * pero se deja preparado por consistencia estructural.
 */
exports.EditarAdministradorDTO = zod_1.z.object({
// Si luego agregas campos (ej. empresaId, conjuntoId, etc.), van aquí
});
/* ===================== SELECT PARA PRISMA ===================== */
/**
 * Select base para evitar traer relaciones pesadas.
 * Si en algún momento agregas relaciones o columnas adicionales,
 * puedes extenderlo fácilmente.
 */
exports.administradorPublicSelect = {
    id: true,
};
/** Helper para castear el result Prisma al tipo público */
function toAdministradorPublico(row) {
    return row;
}
