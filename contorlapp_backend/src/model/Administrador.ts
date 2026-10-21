// src/models/administrador.ts
import { z } from "zod";

import { camposFueraDeEdicionRapida, EditarUsuarioDTO } from "./Usuario";

/** Mismo tipo que Usuario.id */
export type AdministradorId = number;

/**
 * Dominio base (1:1 con el modelo Prisma `Administrador`)
 * No tiene más campos además del id, pero lo definimos igual
 * para mantener consistencia y escalabilidad futura.
 */
export interface AdministradorDominio {
  id: AdministradorId;
}

/** Tipo público (idéntico, pero preparado por consistencia) */
export type AdministradorPublico = AdministradorDominio;

/* ===================== DTOs ===================== */

/**
 * DTO para creación del Administrador.
 * Requiere un Usuario ya creado con rol = "administrador".
 */
export const CrearAdministradorDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
  conjuntoId: z.string().trim().min(3),
});

/**
 * Edicion rapida (PATCH /gerente/administradores/:id): solo datos personales.
 * Rol, estado y contrasena van por la edicion completa del usuario; los conjuntos,
 * por la asignacion o el reemplazo de administradores. Jornada y patron se quedan
 * fuera porque se normalizan juntos en `editarUsuario`.
 */
export const EditarAdministradorDTO = EditarUsuarioDTO.pick({
  nombre: true,
  correo: true,
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
}).extend(camposFueraDeEdicionRapida);

/** POST /gerente/administradores/reemplazos */
export const ReemplazarAdministradoresDTO = z.object({
  reemplazos: z
    .array(
      z.object({
        conjuntoId: z.string().trim().min(3),
        nuevoAdminId: z.number().int().positive(),
      }),
    )
    .superRefine((reemplazos, ctx) => {
      const vistos = new Set<string>();
      for (const { conjuntoId } of reemplazos) {
        if (vistos.has(conjuntoId)) {
          ctx.addIssue({
            code: "custom",
            message: `El conjunto ${conjuntoId} aparece más de una vez en los reemplazos.`,
          });
          return;
        }
        vistos.add(conjuntoId);
      }
    }),
});

/* ===================== SELECT PARA PRISMA ===================== */

/**
 * Select base para evitar traer relaciones pesadas.
 * Si en algún momento agregas relaciones o columnas adicionales,
 * puedes extenderlo fácilmente.
 */
export const administradorPublicSelect = {
  id: true,
} as const;

/** Helper para castear el result Prisma al tipo público */
export function toAdministradorPublico<T extends Record<keyof typeof administradorPublicSelect, any>>(
  row: T
): AdministradorPublico {
  return row;
}
