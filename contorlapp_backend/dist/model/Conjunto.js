"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.conjuntoPublicSelect = exports.EditarConjuntoDTO = exports.CrearConjuntoDTO = exports.UbicacionConElementosDTO = exports.HorarioDTO = void 0;
exports.toConjuntoPublico = toConjuntoPublico;
// src/model/Conjunto.ts
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/** Tipo horario (usar enums de Prisma) */
exports.HorarioDTO = zod_1.z
    .object({
    dia: zod_1.z.nativeEnum(client_1.DiaSemana),
    horaApertura: zod_1.z
        .string()
        .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm"),
    horaCierre: zod_1.z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm"),
    descansoInicio: zod_1.z
        .string()
        .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm")
        .optional()
        .nullable(),
    descansoFin: zod_1.z
        .string()
        .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm")
        .optional()
        .nullable(),
})
    .refine(({ horaApertura, horaCierre }) => horaApertura < horaCierre, {
    message: "horaApertura debe ser menor que horaCierre",
    path: ["horaCierre"],
})
    .refine((d) => {
    // si uno viene, el otro también
    if ((d.descansoInicio && !d.descansoFin) ||
        (!d.descansoInicio && d.descansoFin)) {
        return false;
    }
    return true;
}, {
    message: "Si defines descanso, debes enviar descansoInicio y descansoFin.",
    path: ["descansoInicio"],
})
    .refine((d) => {
    if (!d.descansoInicio || !d.descansoFin)
        return true;
    // apertura < descansoInicio < descansoFin < cierre
    return (d.horaApertura < d.descansoInicio &&
        d.descansoInicio < d.descansoFin &&
        d.descansoFin < d.horaCierre);
}, {
    message: "Descanso debe estar dentro de la jornada: apertura < descansoInicio < descansoFin < cierre.",
    path: ["descansoInicio"],
});
/* ===================== DTOs ===================== */
exports.UbicacionConElementosDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2, "El nombre de la ubicación es obligatorio"),
    elementos: zod_1.z.array(zod_1.z.string().min(2)).default([]), // nombres de los elementos
});
exports.CrearConjuntoDTO = zod_1.z.object({
    nit: zod_1.z.string().min(3),
    nombre: zod_1.z.string().min(2),
    direccion: zod_1.z.string().min(3),
    correo: zod_1.z.string().email(),
    administradorId: zod_1.z.string().min(1).optional().nullable(),
    fechaInicioContrato: zod_1.z.coerce.date().optional(),
    fechaFinContrato: zod_1.z.coerce.date().optional(),
    activo: zod_1.z.boolean().default(true),
    tipoServicio: zod_1.z.array(zod_1.z.nativeEnum(client_1.TipoServicio)).default([]),
    valorMensual: zod_1.z.coerce.number().positive().optional(),
    consignasEspeciales: zod_1.z.array(zod_1.z.string()).default([]),
    valorAgregado: zod_1.z.array(zod_1.z.string()).default([]),
    horarios: zod_1.z.array(exports.HorarioDTO).optional().default([]),
    ubicaciones: zod_1.z
        .array(zod_1.z.object({
        nombre: zod_1.z.string().min(2),
        elementos: zod_1.z.array(zod_1.z.string().min(1)).optional().default([]),
    }))
        .optional()
        .default([]),
});
exports.EditarConjuntoDTO = zod_1.z.object({
    nombre: zod_1.z.string().min(2).optional(),
    direccion: zod_1.z.string().min(3).optional(),
    correo: zod_1.z.string().email().optional(),
    administradorId: zod_1.z.string().min(3).optional().nullable(),
    empresaId: zod_1.z.string().min(3).optional().nullable(),
    fechaInicioContrato: zod_1.z.coerce.date().optional().nullable(),
    fechaFinContrato: zod_1.z.coerce.date().optional().nullable(),
    activo: zod_1.z.boolean().optional(),
    tipoServicio: zod_1.z.array(zod_1.z.nativeEnum(client_1.TipoServicio)).optional(),
    valorMensual: zod_1.z.coerce.number().positive().optional().nullable(),
    consignasEspeciales: zod_1.z.array(zod_1.z.string()).optional(),
    valorAgregado: zod_1.z.array(zod_1.z.string()).optional(),
    horarios: zod_1.z.array(exports.HorarioDTO).optional(),
    operariosIds: zod_1.z.array(zod_1.z.string()).optional(),
    ubicaciones: zod_1.z.array(exports.UbicacionConElementosDTO).optional(),
});
/* ===================== SELECT ===================== */
exports.conjuntoPublicSelect = {
    nit: true,
    nombre: true,
    direccion: true,
    correo: true,
    administradorId: true,
    empresaId: true,
    fechaInicioContrato: true,
    fechaFinContrato: true,
    activo: true,
    tipoServicio: true,
    valorMensual: true,
    consignasEspeciales: true,
    valorAgregado: true,
    horarios: {
        select: {
            dia: true,
            horaApertura: true,
            horaCierre: true,
            descansoInicio: true,
            descansoFin: true,
        },
    },
};
function toConjuntoPublico(row) {
    return row;
}
