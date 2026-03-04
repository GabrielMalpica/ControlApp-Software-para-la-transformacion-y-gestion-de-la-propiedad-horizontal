"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.insumoPublicSelect = exports.FiltroInsumoDTO = exports.EditarInsumoDTO = exports.CrearInsumoDTO = void 0;
exports.toInsumoPublico = toInsumoPublico;
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/* ===================== DTOs ===================== */
/** Crear insumo (normalmente dentro del catálogo de una empresa) */
exports.CrearInsumoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2),
    unidad: zod_1.z.string().min(1), // ej. "kg", "L", "unidad"
    categoria: zod_1.z.nativeEnum(client_1.CategoriaInsumo),
    umbralBajo: zod_1.z.coerce.number().int().min(0).optional(), // 👈 cambia aquí
    empresaId: zod_1.z.string().min(3).optional(),
});
/** Editar insumo */
exports.EditarInsumoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2).optional(),
    unidad: zod_1.z.string().min(1).optional(),
    categoria: zod_1.z.nativeEnum(client_1.CategoriaInsumo).optional(),
    umbralBajo: zod_1.z.coerce.number().int().min(0).optional(), // 👈 también aquí
    empresaId: zod_1.z.string().min(3).optional().nullable(),
});
/** Filtro para búsquedas */
exports.FiltroInsumoDTO = zod_1.z.object({
    empresaId: zod_1.z.string().optional(),
    nombre: zod_1.z.string().optional(),
    categoria: zod_1.z.nativeEnum(client_1.CategoriaInsumo).optional(),
});
/* ===================== SELECT BASE PARA PRISMA ===================== */
exports.insumoPublicSelect = {
    id: true,
    nombre: true,
    unidad: true,
    categoria: true,
    umbralBajo: true,
    empresaId: true,
};
/** Helper para castear el resultado Prisma */
function toInsumoPublico(row) {
    return row;
}
