// src/model/Conjunto.ts
import { z } from "zod";
import { DiaSemana, TipoServicio } from "../generated/prisma";

/** Tipo horario (usar enums de Prisma) */
export const HorarioDTO = z
  .object({
    dia: z.nativeEnum(DiaSemana),
    horaApertura: z
      .string()
      .regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm"),
    horaCierre: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Formato HH:mm"),
  })
  .refine(({ horaApertura, horaCierre }) => horaApertura < horaCierre, {
    message: "horaApertura debe ser menor que horaCierre",
    path: ["horaCierre"],
  });

/** Dominio base alineado a Prisma */
export interface ConjuntoDominio {
  nit: string;
  nombre: string;
  direccion: string;
  correo: string;
  administradorId?: string | null;
  empresaId?: string | null;

  fechaInicioContrato?: Date | null;
  fechaFinContrato?: Date | null;
  activo: boolean;
  tipoServicio: TipoServicio[];
  valorMensual?: number | null;
  consignasEspeciales: string[];
  valorAgregado: string[];
}

/** Público: igual que dominio + (opcional) horarios */
export type ConjuntoPublico = ConjuntoDominio & {
  horarios?: { dia: DiaSemana; horaApertura: string; horaCierre: string }[];
};

/* ===================== DTOs ===================== */

export const UbicacionConElementosDTO = z.object({
  nombre: z.string().min(2, "El nombre de la ubicación es obligatorio"),
  elementos: z.array(z.string().min(2)).default([]), // nombres de los elementos
});
export type UbicacionConElementos = z.infer<typeof UbicacionConElementosDTO>;

export const CrearConjuntoDTO = z.object({
  nit: z.string().min(3),
  nombre: z.string().min(2),
  direccion: z.string().min(3),
  correo: z.string().email(),

  administradorId: z.string().min(1).optional().nullable(),

  fechaInicioContrato: z.coerce.date().optional(),
  fechaFinContrato: z.coerce.date().optional(),
  activo: z.boolean().default(true),
  tipoServicio: z.array(z.nativeEnum(TipoServicio)).default([]),
  valorMensual: z.coerce.number().positive().optional(),
  consignasEspeciales: z.array(z.string()).default([]),
  valorAgregado: z.array(z.string()).default([]),

  horarios: z.array(HorarioDTO).optional().default([]),

  ubicaciones: z
    .array(
      z.object({
        nombre: z.string().min(2),
        elementos: z.array(z.string().min(1)).optional().default([]),
      })
    )
    .optional()
    .default([]),
});

export const EditarConjuntoDTO = z.object({
  nombre: z.string().min(2).optional(),
  direccion: z.string().min(3).optional(),
  correo: z.string().email().optional(),
  administradorId: z.string().min(3).optional().nullable(),
  empresaId: z.string().min(3).optional().nullable(),

  fechaInicioContrato: z.coerce.date().optional().nullable(),
  fechaFinContrato: z.coerce.date().optional().nullable(),
  activo: z.boolean().optional(),
  tipoServicio: z.array(z.nativeEnum(TipoServicio)).optional(),
  valorMensual: z.coerce.number().positive().optional().nullable(),
  consignasEspeciales: z.array(z.string()).optional(),
  valorAgregado: z.array(z.string()).optional(),

  horarios: z.array(HorarioDTO).optional(),
});

/* ===================== SELECT ===================== */

export const conjuntoPublicSelect = {
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
} as const;

export function toConjuntoPublico<
  T extends Record<keyof typeof conjuntoPublicSelect, any>
>(row: T): ConjuntoPublico {
  return row as ConjuntoPublico;
}
