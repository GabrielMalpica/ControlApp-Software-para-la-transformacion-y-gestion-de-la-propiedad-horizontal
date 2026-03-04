"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.FiltroCronogramaDTO = exports.EditarCronogramaDTO = exports.CrearCronogramaDTO = void 0;
// src/models/cronograma.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/**
 * DTO para crear/actualizar un cronograma (lote de tareas) dentro de un conjunto.
 * Puedes usarlo para crear el borrador mensual o para cargar correctivas.
 */
exports.CrearCronogramaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3), // NIT del conjunto
    // opcional: si es un borrador mensual
    borrador: zod_1.z.boolean().default(true),
    periodoAnio: zod_1.z.number().int().optional(),
    periodoMes: zod_1.z.number().int().min(1).max(12).optional(),
    tareas: zod_1.z.array(zod_1.z.object({
        descripcion: zod_1.z.string().min(3),
        // ventana y duración
        fechaInicio: zod_1.z.coerce.date(),
        fechaFin: zod_1.z.coerce.date(),
        duracionHoras: zod_1.z.number().int().positive(),
        // asignaciones
        ubicacionId: zod_1.z.number().int().positive(),
        elementoId: zod_1.z.number().int().positive(),
        operarioId: zod_1.z.number().int().positive().optional(),
        supervisorId: zod_1.z.number().int().positive().optional(),
        // tipo/frecuencia (si es preventiva)
        tipo: zod_1.z.nativeEnum(client_1.TipoTarea).default("CORRECTIVA"),
        frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
        // agrupación por bloques (si fue partida)
        grupoPlanId: zod_1.z.string().uuid().optional(),
        bloqueIndex: zod_1.z.number().int().positive().optional(),
        bloquesTotales: zod_1.z.number().int().positive().optional(),
        // extras
        observaciones: zod_1.z.string().optional(),
    }).refine((t) => +t.fechaFin > +t.fechaInicio, {
        message: "fechaFin debe ser mayor que fechaInicio",
        path: ["fechaFin"],
    })).min(1),
});
/**
 * DTO para editar tareas dentro de un cronograma (lote partial update).
 * Útil para mover bloques, cambiar duración, estado, etc.
 */
exports.EditarCronogramaDTO = zod_1.z.object({
    tareas: zod_1.z.array(zod_1.z.object({
        id: zod_1.z.number().int().positive(),
        descripcion: zod_1.z.string().min(3).optional(),
        fechaInicio: zod_1.z.coerce.date().optional(),
        fechaFin: zod_1.z.coerce.date().optional(),
        duracionHoras: zod_1.z.number().int().positive().optional(),
        estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
        observaciones: zod_1.z.string().optional().nullable(),
        // reasignaciones
        operarioId: zod_1.z.number().int().positive().optional().nullable(),
        supervisorId: zod_1.z.number().int().positive().optional().nullable(),
        ubicacionId: zod_1.z.number().int().positive().optional(),
        elementoId: zod_1.z.number().int().positive().optional(),
        // tipo/frecuencia (si cambió)
        tipo: zod_1.z.nativeEnum(client_1.TipoTarea).optional(),
        frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional().nullable(),
        // bloques (si cambió la partición)
        grupoPlanId: zod_1.z.string().uuid().optional().nullable(),
        bloqueIndex: zod_1.z.number().int().positive().optional().nullable(),
        bloquesTotales: zod_1.z.number().int().positive().optional().nullable(),
    }).refine((t) => {
        if (!t.fechaInicio || !t.fechaFin)
            return true;
        return +t.fechaFin > +t.fechaInicio;
    }, {
        message: "fechaFin debe ser mayor que fechaInicio",
        path: ["fechaFin"],
    })).min(1),
});
/**
 * DTO para filtrar/consultar cronograma.
 * Útil para endpoints tipo: /cronograma?conjuntoId=&periodoMes=&periodoAnio=&dia=...
 */
exports.FiltroCronogramaDTO = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    // rango temporal
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    // o bien por periodo de borrador
    periodoAnio: zod_1.z.number().int().optional(),
    periodoMes: zod_1.z.number().int().min(1).max(12).optional(),
    borrador: zod_1.z.boolean().optional(),
    // filtros adicionales
    estado: zod_1.z.nativeEnum(client_1.EstadoTarea).optional(),
    tipo: zod_1.z.nativeEnum(client_1.TipoTarea).optional(),
    frecuencia: zod_1.z.nativeEnum(client_1.Frecuencia).optional(),
    operarioId: zod_1.z.number().int().optional(),
    supervisorId: zod_1.z.number().int().optional(),
    ubicacionId: zod_1.z.number().int().optional(),
    elementoId: zod_1.z.number().int().optional(),
})
    .refine((f) => {
    // si viene uno de {fechaInicio, fechaFin}, que vengan ambos
    if ((f.fechaInicio && !f.fechaFin) || (!f.fechaInicio && f.fechaFin))
        return false;
    return true;
}, {
    message: "Debe enviar ambos: fechaInicio y fechaFin, o ninguno.",
});
