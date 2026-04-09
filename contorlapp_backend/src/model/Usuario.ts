import { z } from "zod";
/**
 * Importamos los enums directamente del client generado por Prisma,
 * según tu generator (output: ../src/generated/prisma).
 */
import {
  EPS,
  DiaSemana,
  EstadoCivil,
  FondoPension,
  JornadaLaboral,
  PatronJornada,
  TallaCalzado,
  TallaCamisa,
  TallaPantalon,
  TipoContrato,
  TipoSangre,
  Rol, // aunque en el modelo 'rol' es String, usamos este enum para validar
} from "@prisma/client";

/**
 * Nota: En tu Prisma, Usuario.id es Int @id (SIN autoincrement).
 * Por tanto, para crear un usuario debes proveer el id manualmente.
 */
export type UsuarioId = string;

/** Tipado de dominio alineado 1:1 con tu modelo (sin relaciones) */
export interface UsuarioDominio {
  id: UsuarioId;
  nombre: string;
  correo: string;
  contrasena: string;
  rol: `${Rol}` | string;

  activo: boolean; // ✅ NUEVO

  telefono: bigint;
  fechaNacimiento: Date;
  direccion?: string | null;
  estadoCivil?: EstadoCivil | null;
  numeroHijos?: number | null;
  padresVivos?: boolean | null;
  tipoSangre?: TipoSangre | null;
  eps?: EPS | null;
  fondoPensiones?: FondoPension | null;
  tallaCamisa?: TallaCamisa | null;
  tallaPantalon?: TallaPantalon | null;
  tallaCalzado?: TallaCalzado | null;
  tipoContrato?: TipoContrato | null;

  jornadaLaboral?: JornadaLaboral | null;
  patronJornada?: PatronJornada | null;
  disponibilidadPeriodos?: Array<{
    id?: number;
    fechaInicio: Date;
    fechaFin?: Date | null;
    trabajaDomingo: boolean;
    diaDescanso?: DiaSemana | null;
    observaciones?: string | null;
  }>;
}

/** Lo que devolvemos públicamente (sin contraseña) */
export type UsuarioPublico = Omit<UsuarioDominio, "contrasena">;

/** ---------- ZOD DTOs ---------- */

/**
 * Como 'id' no es autoincrement, lo exigimos al crear.
 * telefono es BigInt: usamos z.coerce.bigint() para aceptar string/number.
 * rol en BD es String, pero validamos contra enum Rol para consistencia.
 */
export const CrearUsuarioDTO = z.object({
  id: z.string().min(5, "La cédula debe tener al menos 5 caracteres"),
  nombre: z.string().min(1, "El nombre es obligatorio"),
  correo: z.string().email("Correo inválido"),
  contrasena: z.string().min(8, "La contraseña debe tener mínimo 8 caracteres"),
  rol: z.nativeEnum(Rol),
  telefono: z.coerce.bigint(),
  fechaNacimiento: z.coerce.date(),
  activo: z.boolean().optional(),
  patronJornada: z.nativeEnum(PatronJornada).optional().nullable(),
  disponibilidadPeriodos: z
    .array(
      z.object({
        id: z.number().int().positive().optional(),
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date().optional().nullable(),
        trabajaDomingo: z.boolean().default(false),
        diaDescanso: z.nativeEnum(DiaSemana).optional().nullable(),
        observaciones: z.string().optional().nullable(),
      }),
    )
    .optional(),

  direccion: z.string().optional().nullable(),
  estadoCivil: z.nativeEnum(EstadoCivil).optional().nullable(),
  numeroHijos: z.coerce.number().int().min(0).optional(),
  padresVivos: z.boolean().optional(),

  tipoSangre: z.nativeEnum(TipoSangre).optional().nullable(),
  eps: z.nativeEnum(EPS).optional().nullable(),
  fondoPensiones: z.nativeEnum(FondoPension).optional().nullable(),

  // 🔹 Ahora las tallas son OPCIONALES
  tallaCamisa: z.nativeEnum(TallaCamisa).optional().nullable(),
  tallaPantalon: z.nativeEnum(TallaPantalon).optional().nullable(),
  tallaCalzado: z.nativeEnum(TallaCalzado).optional().nullable(),

  tipoContrato: z.nativeEnum(TipoContrato).optional().nullable(),
  jornadaLaboral: z.nativeEnum(JornadaLaboral).optional().nullable(),
});

/**
 * Para editar: todos opcionales. Si permites cambio de id, deja comentado.
 * Mantenemos la validación de rol con el enum Rol aunque sea String en BD.
 */
export const EditarUsuarioDTO = z.object({
  // id: z.number().int().positive().optional(), // normalmente NO se edita
  nombre: z.string().min(2).optional(),
  correo: z
    .string()
    .email()
    .transform((v) => v.toLowerCase().trim())
    .optional(),
  contrasena: z.string().min(8).optional(),
  rol: z.nativeEnum(Rol).optional(),
  telefono: z.coerce.bigint().optional(),
  fechaNacimiento: z.coerce.date().optional(),
  direccion: z.string().optional().nullable(),
  estadoCivil: z.nativeEnum(EstadoCivil).optional().nullable(),
  numeroHijos: z.number().int().min(0).optional(),
  padresVivos: z.boolean().optional(),
  tipoSangre: z.nativeEnum(TipoSangre).optional().nullable(),
  eps: z.nativeEnum(EPS).optional().nullable(),
  fondoPensiones: z.nativeEnum(FondoPension).optional().nullable(),
  tallaCamisa: z.nativeEnum(TallaCamisa).optional().nullable(),
  tallaPantalon: z.nativeEnum(TallaPantalon).optional().nullable(),
  tallaCalzado: z.nativeEnum(TallaCalzado).optional().nullable(),
  tipoContrato: z.nativeEnum(TipoContrato).optional().nullable(),
  jornadaLaboral: z.nativeEnum(JornadaLaboral).optional().nullable(),
  activo: z.boolean().optional(),
  patronJornada: z.nativeEnum(PatronJornada).optional().nullable(),
  disponibilidadPeriodos: z
    .array(
      z.object({
        id: z.number().int().positive().optional(),
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date().optional().nullable(),
        trabajaDomingo: z.boolean().default(false),
        diaDescanso: z.nativeEnum(DiaSemana).optional().nullable(),
        observaciones: z.string().optional().nullable(),
      }),
    )
    .optional(),
});

/** ---------- SELECT reutilizable para Prisma (oculta contrasena) ---------- */
export const usuarioPublicSelect = {
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
        orderBy: [{ nombre: "asc" as const }],
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
        orderBy: [{ fechaInicio: "desc" as const }],
      },
    },
  },
} as any;

/** Helper para castear el result de Prisma con ese select a UsuarioPublico */
export function toUsuarioPublico(row: any): UsuarioPublico {
  return row as UsuarioPublico;
}

export const ListarUsuariosDTO = z.object({
  rol: z
    .nativeEnum(Rol)
    .optional()
    .nullable()
    .transform((v) => (v === null ? undefined : v)),
});
