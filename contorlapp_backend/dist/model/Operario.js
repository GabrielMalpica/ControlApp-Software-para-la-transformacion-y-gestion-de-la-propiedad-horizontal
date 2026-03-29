"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.operarioPublicSelect = exports.EditarOperarioDTO = exports.CrearOperarioDTO = exports.LIMITE_SEMANAL_HORAS = void 0;
exports.toOperarioPublico = toOperarioPublico;
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
/** Constante que ya usabas en la clase */
exports.LIMITE_SEMANAL_HORAS = 42;
/* ===================== DTOs (Zod) ===================== */
/**
 * CrearOperarioDTO: solo campos propios de Operario.
 * OJO: La creación del Usuario (nombre, correo, etc.) va en su propio DTO/flow.
 */
exports.CrearOperarioDTO = zod_1.z.object({
    Id: zod_1.z.string().min(1, "El id (cédula) del usuario es obligatorio"),
    funciones: zod_1.z.array(zod_1.z.nativeEnum(client_1.TipoFuncion)).nonempty(),
    cursoSalvamentoAcuatico: zod_1.z.boolean(),
    urlEvidenciaSalvamento: zod_1.z.string().url().optional(),
    cursoAlturas: zod_1.z.boolean(),
    urlEvidenciaAlturas: zod_1.z.string().url().optional(),
    examenIngreso: zod_1.z.boolean(),
    urlEvidenciaExamenIngreso: zod_1.z.string().url().optional(),
    fechaIngreso: zod_1.z.coerce.date(),
    fechaSalida: zod_1.z.coerce.date().optional(),
    fechaUltimasVacaciones: zod_1.z.coerce.date().optional(),
    observaciones: zod_1.z.string().optional(),
    disponibilidadPeriodos: zod_1.z
        .array(zod_1.z.object({
        fechaInicio: zod_1.z.coerce.date(),
        fechaFin: zod_1.z.coerce.date().optional().nullable(),
        trabajaDomingo: zod_1.z.boolean().default(false),
        diaDescanso: zod_1.z.nativeEnum(client_1.DiaSemana).optional().nullable(),
        observaciones: zod_1.z.string().optional().nullable(),
    }))
        .optional()
        .default([]),
});
/** Edición parcial */
exports.EditarOperarioDTO = zod_1.z.object({
    funciones: zod_1.z.array(zod_1.z.nativeEnum(client_1.TipoFuncion)).nonempty().optional(),
    cursoSalvamentoAcuatico: zod_1.z.boolean().optional(),
    urlEvidenciaSalvamento: zod_1.z.string().url().optional().nullable(),
    cursoAlturas: zod_1.z.boolean().optional(),
    urlEvidenciaAlturas: zod_1.z.string().url().optional().nullable(),
    examenIngreso: zod_1.z.boolean().optional(),
    urlEvidenciaExamenIngreso: zod_1.z.string().url().optional().nullable(),
    fechaIngreso: zod_1.z.coerce.date().optional(),
    fechaSalida: zod_1.z.coerce.date().optional().nullable(),
    fechaUltimasVacaciones: zod_1.z.coerce.date().optional().nullable(),
    observaciones: zod_1.z.string().optional().nullable(),
    empresaId: zod_1.z.string().min(3).optional(),
    disponibilidadPeriodos: zod_1.z
        .array(zod_1.z.object({
        id: zod_1.z.number().int().positive().optional(),
        fechaInicio: zod_1.z.coerce.date(),
        fechaFin: zod_1.z.coerce.date().optional().nullable(),
        trabajaDomingo: zod_1.z.boolean().default(false),
        diaDescanso: zod_1.z.nativeEnum(client_1.DiaSemana).optional().nullable(),
        observaciones: zod_1.z.string().optional().nullable(),
    }))
        .optional(),
});
/* ============== Select estándar para Prisma ============== */
/**
 * Úsalo en services para no traer relaciones ni campos extra.
 * (El shape coincide con OperarioPublico.)
 */
exports.operarioPublicSelect = {
    id: true,
    funciones: true,
    cursoSalvamentoAcuatico: true,
    urlEvidenciaSalvamento: true,
    cursoAlturas: true,
    urlEvidenciaAlturas: true,
    examenIngreso: true,
    urlEvidenciaExamenIngreso: true,
    fechaIngreso: true,
    fechaSalida: true,
    fechaUltimasVacaciones: true,
    observaciones: true,
    empresaId: true,
    disponibilidadPeriodos: {
        select: {
            id: true,
            fechaInicio: true,
            fechaFin: true,
            trabajaDomingo: true,
            diaDescanso: true,
            observaciones: true,
        },
        orderBy: [{ fechaInicio: "desc" }],
    },
};
/** Helper para castear el resultado del select a tu tipo público */
function toOperarioPublico(row) {
    return row;
}
