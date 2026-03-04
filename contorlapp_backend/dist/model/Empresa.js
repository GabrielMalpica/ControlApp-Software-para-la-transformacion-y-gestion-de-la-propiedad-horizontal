"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.empresaPublicSelect = exports.FiltroEmpresaDTO = exports.EditarEmpresaDTO = exports.CrearEmpresaDTO = void 0;
exports.toEmpresaPublica = toEmpresaPublica;
// src/models/empresa.ts
const zod_1 = require("zod");
/* ===================== DTOs ===================== */
/** Crear empresa */
exports.CrearEmpresaDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(3),
    nit: zod_1.z.string().min(3),
    // opcional: si no lo envías, aplica el default de Prisma (46)
    limiteHorasSemana: zod_1.z.coerce.number().int().min(1).max(84).optional(),
});
/** Editar empresa */
exports.EditarEmpresaDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(3).optional(),
    nit: zod_1.z.string().min(3).optional(), // normalmente no se cambia
    limiteHorasSemana: zod_1.z.coerce.number().int().min(1).max(84).optional(), // NUEVO
});
/** Filtro de búsqueda de empresas */
exports.FiltroEmpresaDTO = zod_1.z.object({
    nit: zod_1.z.string().optional(),
    nombre: zod_1.z.string().optional(),
});
/* ===================== SELECT BASE PARA PRISMA ===================== */
exports.empresaPublicSelect = {
    id: true,
    nombre: true,
    nit: true,
    limiteHorasSemana: true, // NUEVO
};
/** Helper para castear el resultado de Prisma al tipo público */
function toEmpresaPublica(row) {
    return row;
}
