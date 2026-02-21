import { z } from "zod";
import {
  TipoFuncion,
} from "../generated/prisma";


/** Mismo tipo de ID que en Prisma: Int (misma FK que Usuario.id) */
export type OperarioId = number;

/** Constante que ya usabas en la clase */
export let LIMITE_SEMANAL_HORAS = 42 as const;

/** Dominio 1:1 con la tabla Operario (sin relaciones navegadas) */
export interface OperarioDominio {
  id: OperarioId;                 // FK a Usuario.id
  funciones: TipoFuncion[];       // enum[]
  cursoSalvamentoAcuatico: boolean;
  urlEvidenciaSalvamento?: string | null;
  cursoAlturas: boolean;
  urlEvidenciaAlturas?: string | null;
  examenIngreso: boolean;
  urlEvidenciaExamenIngreso?: string | null;
  fechaIngreso: Date;
  fechaSalida?: Date | null;
  fechaUltimasVacaciones?: Date | null;
  observaciones?: string | null;

  empresaId: string;
}

/** Lo que puedes devolver públicamente */
export type OperarioPublico = OperarioDominio;

/* ===================== DTOs (Zod) ===================== */

/**
 * CrearOperarioDTO: solo campos propios de Operario.
 * OJO: La creación del Usuario (nombre, correo, etc.) va en su propio DTO/flow.
 */
export const CrearOperarioDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
  funciones: z.array(z.nativeEnum(TipoFuncion)).nonempty(),
  cursoSalvamentoAcuatico: z.boolean(),
  urlEvidenciaSalvamento: z.string().url().optional(),
  cursoAlturas: z.boolean(),
  urlEvidenciaAlturas: z.string().url().optional(),
  examenIngreso: z.boolean(),
  urlEvidenciaExamenIngreso: z.string().url().optional(),
  fechaIngreso: z.coerce.date(),
  fechaSalida: z.coerce.date().optional(),
  fechaUltimasVacaciones: z.coerce.date().optional(),
  observaciones: z.string().optional(),
});

/** Edición parcial */
export const EditarOperarioDTO = z.object({
  funciones: z.array(z.nativeEnum(TipoFuncion)).nonempty().optional(),
  cursoSalvamentoAcuatico: z.boolean().optional(),
  urlEvidenciaSalvamento: z.string().url().optional().nullable(),
  cursoAlturas: z.boolean().optional(),
  urlEvidenciaAlturas: z.string().url().optional().nullable(),
  examenIngreso: z.boolean().optional(),
  urlEvidenciaExamenIngreso: z.string().url().optional().nullable(),
  fechaIngreso: z.coerce.date().optional(),
  fechaSalida: z.coerce.date().optional().nullable(),
  fechaUltimasVacaciones: z.coerce.date().optional().nullable(),
  observaciones: z.string().optional().nullable(),
  empresaId: z.string().min(3).optional(),
});

/* ============== Select estándar para Prisma ============== */
/**
 * Úsalo en services para no traer relaciones ni campos extra.
 * (El shape coincide con OperarioPublico.)
 */
export const operarioPublicSelect = {
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
} as const;

/** Helper para castear el resultado del select a tu tipo público */
export function toOperarioPublico<T extends Record<keyof typeof operarioPublicSelect, any>>(
  row: T
): OperarioPublico {
  return row;
}
