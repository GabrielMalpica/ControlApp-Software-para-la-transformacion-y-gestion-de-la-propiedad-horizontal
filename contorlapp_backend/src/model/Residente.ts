import { TipoUnidadResidencial } from "@prisma/client";
import { z } from "zod";

export const CrearResidenteManualDTO = z.object({
  conjuntoId: z.string().trim().min(3, "El conjunto es obligatorio"),
  cedula: z.string().trim().min(5, "La cedula es obligatoria"),
  nombre: z.string().trim().min(3, "El nombre es obligatorio"),
  correo: z.string().trim().toLowerCase().email("Correo invalido"),
  telefono: z.string().trim().optional().nullable(),
  tipoUnidad: z.nativeEnum(TipoUnidadResidencial).optional().nullable(),
  sector: z.string().trim().optional().nullable(),
  unidad: z.string().trim().optional().nullable(),
  torre: z.string().trim().optional().nullable(),
  apartamento: z.string().trim().optional().nullable(),
  casa: z.string().trim().optional().nullable(),
});

export const CargaMasivaResidentesBodyDTO = z.object({
  conjuntoId: z.string().trim().min(3, "El conjunto es obligatorio"),
});

export const EditarResidenteDTO = z.object({
  conjuntoId: z.string().trim().min(3, "El conjunto es obligatorio"),
  nombre: z.string().trim().min(3).optional(),
  correo: z.string().trim().toLowerCase().email("Correo invalido").optional(),
  telefono: z.string().trim().optional().nullable(),
  activo: z.boolean().optional(),
  tipoUnidad: z.nativeEnum(TipoUnidadResidencial).optional().nullable(),
  sector: z.string().trim().optional().nullable(),
  unidad: z.string().trim().optional().nullable(),
  torre: z.string().trim().optional().nullable(),
  apartamento: z.string().trim().optional().nullable(),
  casa: z.string().trim().optional().nullable(),
});

export const ListarResidentesQueryDTO = z.object({
  conjuntoId: z.string().trim().min(3, "El conjunto es obligatorio"),
  q: z.string().trim().optional(),
});

export const residentePublicSelect = {
  id: true,
  tipoUnidad: true,
  sector: true,
  unidad: true,
  telefonoContacto: true,
  activo: true,
  creadoEn: true,
  usuario: {
    select: {
      id: true,
      nombre: true,
      correo: true,
      rol: true,
      activo: true,
      requiereCambioContrasena: true,
    },
  },
  conjunto: {
    select: {
      nit: true,
      nombre: true,
    },
  },
} as const;

export type CrearResidenteManualInput = z.infer<typeof CrearResidenteManualDTO>;
export type EditarResidenteInput = z.infer<typeof EditarResidenteDTO>;
