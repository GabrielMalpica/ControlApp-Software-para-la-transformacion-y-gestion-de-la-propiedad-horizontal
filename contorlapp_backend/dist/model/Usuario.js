"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ListarUsuariosDTO = exports.usuarioPublicSelect = exports.EditarUsuarioDTO = exports.CrearUsuarioDTO = void 0;
exports.toUsuarioPublico = toUsuarioPublico;
const zod_1 = require("zod");
/**
 * Importamos los enums directamente del client generado por Prisma,
 * según tu generator (output: ../src/generated/prisma).
 */
const client_1 = require("@prisma/client");
/** ---------- ZOD DTOs ---------- */
/**
 * Como 'id' no es autoincrement, lo exigimos al crear.
 * telefono es BigInt: usamos z.coerce.bigint() para aceptar string/number.
 * rol en BD es String, pero validamos contra enum Rol para consistencia.
 */
exports.CrearUsuarioDTO = zod_1.z.object({
    id: zod_1.z.string().min(5, "La cédula debe tener al menos 5 caracteres"),
    nombre: zod_1.z.string().min(1, "El nombre es obligatorio"),
    correo: zod_1.z.string().email("Correo inválido"),
    contrasena: zod_1.z.string().min(8, "La contraseña debe tener mínimo 8 caracteres"),
    rol: zod_1.z.nativeEnum(client_1.Rol),
    telefono: zod_1.z.coerce.bigint(),
    fechaNacimiento: zod_1.z.coerce.date(),
    activo: zod_1.z.boolean().optional(),
    patronJornada: zod_1.z.nativeEnum(client_1.PatronJornada).optional().nullable(),
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
    direccion: zod_1.z.string().optional().nullable(),
    estadoCivil: zod_1.z.nativeEnum(client_1.EstadoCivil).optional().nullable(),
    numeroHijos: zod_1.z.coerce.number().int().min(0).optional(),
    padresVivos: zod_1.z.boolean().optional(),
    tipoSangre: zod_1.z.nativeEnum(client_1.TipoSangre).optional().nullable(),
    eps: zod_1.z.nativeEnum(client_1.EPS).optional().nullable(),
    fondoPensiones: zod_1.z.nativeEnum(client_1.FondoPension).optional().nullable(),
    // 🔹 Ahora las tallas son OPCIONALES
    tallaCamisa: zod_1.z.nativeEnum(client_1.TallaCamisa).optional().nullable(),
    tallaPantalon: zod_1.z.nativeEnum(client_1.TallaPantalon).optional().nullable(),
    tallaCalzado: zod_1.z.nativeEnum(client_1.TallaCalzado).optional().nullable(),
    tipoContrato: zod_1.z.nativeEnum(client_1.TipoContrato).optional().nullable(),
    jornadaLaboral: zod_1.z.nativeEnum(client_1.JornadaLaboral).optional().nullable(),
});
/**
 * Para editar: todos opcionales. Si permites cambio de id, deja comentado.
 * Mantenemos la validación de rol con el enum Rol aunque sea String en BD.
 */
exports.EditarUsuarioDTO = zod_1.z.object({
    // id: z.number().int().positive().optional(), // normalmente NO se edita
    nombre: zod_1.z.string().min(2).optional(),
    correo: zod_1.z
        .string()
        .email()
        .transform((v) => v.toLowerCase().trim())
        .optional(),
    contrasena: zod_1.z.string().min(8).optional(),
    rol: zod_1.z.nativeEnum(client_1.Rol).optional(),
    telefono: zod_1.z.coerce.bigint().optional(),
    fechaNacimiento: zod_1.z.coerce.date().optional(),
    direccion: zod_1.z.string().optional().nullable(),
    estadoCivil: zod_1.z.nativeEnum(client_1.EstadoCivil).optional().nullable(),
    numeroHijos: zod_1.z.number().int().min(0).optional(),
    padresVivos: zod_1.z.boolean().optional(),
    tipoSangre: zod_1.z.nativeEnum(client_1.TipoSangre).optional().nullable(),
    eps: zod_1.z.nativeEnum(client_1.EPS).optional().nullable(),
    fondoPensiones: zod_1.z.nativeEnum(client_1.FondoPension).optional().nullable(),
    tallaCamisa: zod_1.z.nativeEnum(client_1.TallaCamisa).optional().nullable(),
    tallaPantalon: zod_1.z.nativeEnum(client_1.TallaPantalon).optional().nullable(),
    tallaCalzado: zod_1.z.nativeEnum(client_1.TallaCalzado).optional().nullable(),
    tipoContrato: zod_1.z.nativeEnum(client_1.TipoContrato).optional().nullable(),
    jornadaLaboral: zod_1.z.nativeEnum(client_1.JornadaLaboral).optional().nullable(),
    activo: zod_1.z.boolean().optional(),
    patronJornada: zod_1.z.nativeEnum(client_1.PatronJornada).optional().nullable(),
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
/** ---------- SELECT reutilizable para Prisma (oculta contrasena) ---------- */
exports.usuarioPublicSelect = {
    id: true,
    nombre: true,
    correo: true,
    rol: true,
    activo: true,
    telefono: true,
    fechaNacimiento: true,
    direccion: true,
    estadoCivil: true,
    numeroHijos: true,
    padresVivos: true,
    tipoSangre: true,
    eps: true,
    fondoPensiones: true,
    tallaCamisa: true,
    tallaPantalon: true,
    tallaCalzado: true,
    tipoContrato: true,
    jornadaLaboral: true,
    patronJornada: true,
    operario: {
        select: {
            conjuntos: {
                select: {
                    nombre: true,
                },
                orderBy: [{ nombre: "asc" }],
            },
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
        },
    },
};
/** Helper para castear el result de Prisma con ese select a UsuarioPublico */
function toUsuarioPublico(row) {
    return row;
}
exports.ListarUsuariosDTO = zod_1.z.object({
    rol: zod_1.z
        .nativeEnum(client_1.Rol)
        .optional()
        .nullable()
        .transform((v) => (v === null ? undefined : v)),
});
