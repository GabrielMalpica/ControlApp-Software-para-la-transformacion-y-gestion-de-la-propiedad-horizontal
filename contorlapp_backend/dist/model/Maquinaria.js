"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.maquinariaConjuntoSelect = exports.maquinariaCatalogoSelect = exports.FiltroMaquinariaDTO = exports.DevolverMaquinariaDeConjuntoDTO = exports.PrestarMaquinariaAConjuntoDTO = exports.EditarMaquinariaCatalogoDTO = exports.CrearMaquinariaDTO = exports.CrearMaquinariaCatalogoDTO = void 0;
// src/models/maquinaria.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/* ===================== DTOs ===================== */
// Crear maquinaria del catálogo de empresa
exports.CrearMaquinariaCatalogoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2),
    marca: zod_1.z.string().min(2),
    tipo: zod_1.z.nativeEnum(client_1.TipoMaquinaria),
    estado: zod_1.z
        .nativeEnum(client_1.EstadoMaquinaria)
        .optional()
        .default(client_1.EstadoMaquinaria.OPERATIVA),
    // para catálogo empresa:
    empresaId: zod_1.z.string().min(3),
    // opcional: responsable global (en Maquinaria)
    operarioId: zod_1.z.string().optional(),
});
exports.CrearMaquinariaDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2),
    marca: zod_1.z.string().min(2),
    tipo: zod_1.z.nativeEnum(client_1.TipoMaquinaria),
    estado: zod_1.z
        .nativeEnum(client_1.EstadoMaquinaria)
        .optional()
        .default(client_1.EstadoMaquinaria.OPERATIVA),
    // ✅ NUEVO: dueño
    propietarioTipo: zod_1.z
        .nativeEnum(client_1.PropietarioMaquinaria)
        .default(client_1.PropietarioMaquinaria.EMPRESA),
    conjuntoPropietarioId: zod_1.z.string().min(3).optional().nullable(), // nit si dueño = CONJUNTO
});
// Editar maquinaria del catálogo
exports.EditarMaquinariaCatalogoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2).optional(),
    marca: zod_1.z.string().min(2).optional(),
    tipo: zod_1.z.nativeEnum(client_1.TipoMaquinaria).optional(),
    estado: zod_1.z.nativeEnum(client_1.EstadoMaquinaria).optional(),
    operarioId: zod_1.z.string().optional().nullable(),
});
// Asignar (prestar) maquinaria al inventario de un conjunto
exports.PrestarMaquinariaAConjuntoDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive(),
    conjuntoId: zod_1.z.string().min(3),
    fechaDevolucionEstimada: zod_1.z.coerce.date().optional(),
    operarioId: zod_1.z.string().optional(), // responsable de la asignación
});
// Devolver maquinaria del conjunto (cerrar asignación ACTIVA)
exports.DevolverMaquinariaDeConjuntoDTO = zod_1.z.object({
    maquinariaId: zod_1.z.number().int().positive(),
    conjuntoId: zod_1.z.string().min(3),
});
exports.FiltroMaquinariaDTO = zod_1.z.object({
    empresaId: zod_1.z.string().optional(),
    conjuntoId: zod_1.z.string().optional(), // filtra por "prestada a este conjunto" (asignación ACTIVA)
    estado: zod_1.z.nativeEnum(client_1.EstadoMaquinaria).optional(),
    disponible: zod_1.z.boolean().optional(), // derivado
    tipo: zod_1.z.nativeEnum(client_1.TipoMaquinaria).optional(),
    // ✅ NUEVO: filtrar por origen/dueño
    propietarioTipo: zod_1.z.nativeEnum(client_1.PropietarioMaquinaria).optional(), // EMPRESA | CONJUNTO
});
/* ===================== SELECTS ===================== */
exports.maquinariaCatalogoSelect = {
    id: true,
    nombre: true,
    marca: true,
    tipo: true,
    estado: true,
    propietarioTipo: true,
    empresaId: true,
    conjuntoPropietarioId: true,
    operarioId: true,
};
exports.maquinariaConjuntoSelect = {
    id: true,
    conjuntoId: true,
    maquinariaId: true,
    tipoTenencia: true,
    estado: true,
    fechaInicio: true,
    fechaFin: true,
    fechaDevolucionEstimada: true,
    operarioId: true,
    maquinaria: {
        select: { id: true, nombre: true, marca: true, tipo: true, estado: true },
    },
};
