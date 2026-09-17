// src/model/ConjuntoNecesidad.ts
import { z } from "zod";
import { TipoFuncion } from "@prisma/client";
import { HorarioDTO } from "./Conjunto";

/**
 * Necesidad operativa (plaza/cargo) de un conjunto, p.ej. "Todero #1".
 * Reutiliza HorarioDTO (mismo shape que ConjuntoHorario) para el horario
 * especial de la plaza, en vez de duplicar sus validaciones.
 */

function sinDiasDuplicados(horarios: { dia: string }[] | undefined) {
  if (!horarios?.length) return true;
  return new Set(horarios.map((h) => h.dia)).size === horarios.length;
}

export const CrearNecesidadDTO = z
  .object({
    // Casi siempre un solo rol, pero admite combinaciones (p.ej.
    // "Todero-Salvavidas"): el operario asignado debe tener TODOS los
    // roles listados (ver ConjuntoNecesidadService.validarYPrepararOperario).
    roles: z
      .array(z.nativeEnum(TipoFuncion))
      .min(1, "Selecciona al menos un rol"),
    etiqueta: z.string().trim().min(1, "La etiqueta es obligatoria").max(80),
    orden: z.coerce.number().int().min(0).optional().default(0),
    horarioEspecial: z.boolean().optional().default(false),
    horarios: z.array(HorarioDTO).optional().default([]),
    observaciones: z.string().trim().max(500).optional().nullable(),
    // Permite crear la plaza ya ocupada en la misma llamada.
    operarioId: z.string().trim().min(1).optional().nullable(),
  })
  .refine((d) => !d.horarioEspecial || d.horarios.length > 0, {
    message: "Si marcas horario especial, debes configurar al menos un día.",
    path: ["horarios"],
  })
  .refine((d) => sinDiasDuplicados(d.horarios), {
    message: "No repitas el mismo día en los horarios de la plaza.",
    path: ["horarios"],
  });
export type CrearNecesidadInput = z.infer<typeof CrearNecesidadDTO>;

export const EditarNecesidadDTO = z
  .object({
    roles: z
      .array(z.nativeEnum(TipoFuncion))
      .min(1, "Selecciona al menos un rol")
      .optional(),
    etiqueta: z.string().trim().min(1).max(80).optional(),
    orden: z.coerce.number().int().min(0).optional(),
    horarioEspecial: z.boolean().optional(),
    horarios: z.array(HorarioDTO).optional(),
    observaciones: z.string().trim().max(500).optional().nullable(),
    activo: z.boolean().optional(),
  })
  .refine(
    // Rechazo temprano del caso obviamente inválido (activar horario especial
    // sin dar ningún día en el mismo payload). El caso "ya estaba activo y se
    // edita otra cosa" lo valida el servicio contra el estado real en BD.
    (d) => !(d.horarioEspecial === true && d.horarios != null && d.horarios.length === 0),
    {
      message: "Si activas horario especial, debes configurar al menos un día en horarios.",
      path: ["horarios"],
    },
  )
  .refine((d) => sinDiasDuplicados(d.horarios), {
    message: "No repitas el mismo día en los horarios de la plaza.",
    path: ["horarios"],
  });
export type EditarNecesidadInput = z.infer<typeof EditarNecesidadDTO>;

export const AsignarOperarioNecesidadDTO = z.object({
  operarioId: z.string().trim().min(1, "El operario es obligatorio"),
});

export const necesidadPublicSelect = {
  id: true,
  conjuntoId: true,
  roles: true,
  etiqueta: true,
  orden: true,
  horarioEspecial: true,
  activo: true,
  observaciones: true,
  operarioId: true,
  creadoEn: true,
  actualizadoEn: true,
  horarios: {
    select: {
      dia: true,
      horaApertura: true,
      horaCierre: true,
      descansoInicio: true,
      descansoFin: true,
    },
  },
  operario: {
    select: {
      id: true,
      usuario: { select: { nombre: true } },
    },
  },
} as const;
