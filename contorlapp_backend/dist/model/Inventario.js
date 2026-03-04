"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.inventarioInsumoPublicSelect = exports.InsumosBajosFiltroDTO = exports.UnsetUmbralMinimoDTO = exports.SetUmbralMinimoDTO = exports.ConsumirStockDTO = exports.AgregarStockDTO = void 0;
exports.toInventarioInsumoPublico = toInventarioInsumoPublico;
// src/models/inventarioInsumo.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
const decimal_1 = require("../utils/decimal");
/* ===================== DTOs ===================== */
/** Agregar stock (incrementa) */
exports.AgregarStockDTO = zod_1.z.object({
    inventarioId: zod_1.z.number().int().positive(),
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
/** Consumir stock (decrementa) */
exports.ConsumirStockDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().positive(),
});
/** Fijar/actualizar umbral mínimo (por conjunto) */
exports.SetUmbralMinimoDTO = zod_1.z.object({
    inventarioId: zod_1.z.number().int().positive(),
    insumoId: zod_1.z.number().int().positive(),
    umbralMinimo: zod_1.z.coerce.number().int().min(0),
});
/** Quitar umbral mínimo (para volver a usar el global del insumo si existe) */
exports.UnsetUmbralMinimoDTO = zod_1.z.object({
    inventarioId: zod_1.z.number().int().positive(),
    insumoId: zod_1.z.number().int().positive(),
});
/** Filtro para listar insumos bajos */
exports.InsumosBajosFiltroDTO = zod_1.z.object({
    inventarioId: zod_1.z.number().int().positive(),
    categoria: zod_1.z.nativeEnum(client_1.CategoriaInsumo).optional(), // opcional: filtrar por categoría
    nombre: zod_1.z.string().optional(), // opcional: filtro por texto
});
/* ===================== SELECTS ===================== */
exports.inventarioInsumoPublicSelect = {
    id: true,
    inventarioId: true,
    insumoId: true,
    cantidad: true,
    umbralMinimo: true,
};
/** Helper */
function toInventarioInsumoPublico(row) {
    return {
        id: row.id,
        inventarioId: row.inventarioId,
        insumoId: row.insumoId,
        cantidad: (0, decimal_1.decToNumber)(row.cantidad),
        umbralMinimo: row.umbralMinimo != null ? (0, decimal_1.decToNumber)(row.umbralMinimo) : null,
    };
}
