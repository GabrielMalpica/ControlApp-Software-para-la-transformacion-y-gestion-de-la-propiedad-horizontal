// src/models/administrador.ts
import { z } from "zod";

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
  id: z.number().int().positive(), // mismo ID que Usuario.id
});

/**
 * DTO para edición — actualmente no hay campos editables,
 * pero se deja preparado por consistencia estructural.
 */
export const EditarAdministradorDTO = z.object({
  // Si luego agregas campos (ej. empresaId, conjuntoId, etc.), van aquí
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
