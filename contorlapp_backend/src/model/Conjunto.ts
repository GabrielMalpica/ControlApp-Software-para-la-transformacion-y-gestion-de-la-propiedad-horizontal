// src/model/Conjunto.ts
import { z } from "zod";
import { DiaSemana, TipoServicio } from "@prisma/client";

const horaRegex = /^([01]\d|2[0-3]):[0-5]\d$/;

/**
 * Refinamientos compartidos por cualquier franja horaria (apertura, cierre,
 * descanso opcional): los usan tanto HorarioDTO (con día) como
 * HorarioFranjaDTO (sin día, para el horario festivo de una necesidad).
 */
function withFranjaRefinements<
  T extends {
    horaApertura: string;
    horaCierre: string;
    descansoInicio?: string | null;
    descansoFin?: string | null;
  },
>(schema: z.ZodType<T>) {
  return schema
    .refine(({ horaApertura, horaCierre }) => horaApertura < horaCierre, {
      message: "horaApertura debe ser menor que horaCierre",
      path: ["horaCierre"],
    })
    .refine(
      (d) => {
        // si uno viene, el otro también
        if (
          (d.descansoInicio && !d.descansoFin) ||
          (!d.descansoInicio && d.descansoFin)
        ) {
          return false;
        }
        return true;
      },
      {
        message:
          "Si defines descanso, debes enviar descansoInicio y descansoFin.",
        path: ["descansoInicio"],
      }
    )
    .refine(
      (d) => {
        if (!d.descansoInicio || !d.descansoFin) return true;

        // apertura < descansoInicio < descansoFin < cierre
        return (
          d.horaApertura < d.descansoInicio &&
          d.descansoInicio < d.descansoFin &&
          d.descansoFin < d.horaCierre
        );
      },
      {
        message:
          "Descanso debe estar dentro de la jornada: apertura < descansoInicio < descansoFin < cierre.",
        path: ["descansoInicio"],
      }
    );
}

const horarioFranjaBase = z.object({
  horaApertura: z.string().regex(horaRegex, "Formato HH:mm"),
  horaCierre: z.string().regex(horaRegex, "Formato HH:mm"),

  descansoInicio: z
    .string()
    .regex(horaRegex, "Formato HH:mm")
    .optional()
    .nullable(),

  descansoFin: z
    .string()
    .regex(horaRegex, "Formato HH:mm")
    .optional()
    .nullable(),
});

/**
 * Franja horaria sin día: usada por el horario festivo de una necesidad
 * operativa (ConjuntoNecesidadOperario), que no depende del día de la
 * semana (un festivo puede caer cualquier día).
 */
export const HorarioFranjaDTO = withFranjaRefinements(horarioFranjaBase);

/** Tipo horario (usar enums de Prisma) */
export const HorarioDTO = withFranjaRefinements(
  horarioFranjaBase.extend({ dia: z.nativeEnum(DiaSemana) }),
);

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
  horarios?: {
    dia: DiaSemana;
    horaApertura: string;
    horaCierre: string;
    descansoInicio?: string | null;
    descansoFin?: string | null;
  }[];
};

/* ===================== DTOs ===================== */

export const NodoElementoDTO: z.ZodType<{
  id?: number;
  nombre: string;
  hijos?: Array<{ id?: number; nombre: string; hijos?: any[] }>;
}> = z.object({
  id: z.coerce.number().int().positive().optional(),
  nombre: z.string().min(2, "El nombre es obligatorio"),
  hijos: z.lazy(() => z.array(NodoElementoDTO).default([])).optional().default([]),
});

export const UbicacionConElementosDTO = z.object({
  id: z.coerce.number().int().positive().optional(),
  nombre: z.string().min(2, "El nombre de la ubicación es obligatorio"),
  elementos: z.array(NodoElementoDTO).default([]),
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

  // Enlace de Google Maps del conjunto: de ahí salen latitud/longitud para
  // validar que el QR de asistencia se escanee en el sitio.
  ubicacionMapsUrl: z.string().trim().max(1000).optional().nullable(),
  radioAsistenciaMetros: z.coerce.number().int().min(30).max(2000).optional(),

  horarios: z.array(HorarioDTO).optional().default([]),

  ubicaciones: z
    .array(
      z.object({
        nombre: z.string().min(2),
        elementos: z.array(NodoElementoDTO).optional().default([]),
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

  // null o "" borra la ubicación (el QR deja de validarse por distancia).
  ubicacionMapsUrl: z.string().trim().max(1000).optional().nullable(),
  radioAsistenciaMetros: z.coerce.number().int().min(30).max(2000).optional(),

  horarios: z.array(HorarioDTO).optional(),
  operariosIds: z.array(z.string()).optional(),
  ubicaciones: z.array(UbicacionConElementosDTO).optional(),
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
  ubicacionMapsUrl: true,
  latitud: true,
  longitud: true,
  radioAsistenciaMetros: true,

  horarios: {
    select: {
      dia: true,
      horaApertura: true,
      horaCierre: true,
      descansoInicio: true,
      descansoFin: true,
    },
  },
} as const;

export function toConjuntoPublico<
  T extends Record<keyof typeof conjuntoPublicSelect, any>
>(row: T): ConjuntoPublico {
  return row as ConjuntoPublico;
}
