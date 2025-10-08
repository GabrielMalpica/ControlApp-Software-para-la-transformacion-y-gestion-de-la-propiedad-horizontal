// src/models/conjunto.ts
import { z } from "zod";

/** 
 * En Prisma, el campo `nit` es String @id.
 * El campo administradorId es Int? (opcional).
 */
export type ConjuntoNit = string;

/** Dominio base (1:1 con el modelo Prisma, sin relaciones navegadas) */
export interface ConjuntoDominio {
  nit: ConjuntoNit;
  nombre: string;
  direccion: string;
  correo: string;
  administradorId?: number | null;
  empresaId?: string | null;
}

/** Tipo público — idéntico al dominio base (por ahora) */
export type ConjuntoPublico = ConjuntoDominio;

/* ===================== DTOs ===================== */

/** DTO para creación de un conjunto */
export const CrearConjuntoDTO = z.object({
  nit: z.string().min(3), // por ejemplo: "900123456"
  nombre: z.string().min(2),
  direccion: z.string().min(3),
  correo: z.string().email(),
  administradorId: z.number().int().optional(),
  empresaId: z.string().min(3).optional(),
});

/** DTO para edición (todo opcional excepto nit) */
export const EditarConjuntoDTO = z.object({
  nombre: z.string().min(2).optional(),
  direccion: z.string().min(3).optional(),
  correo: z.string().email().optional(),
  administradorId: z.number().int().optional().nullable(),
  empresaId: z.string().min(3).optional().nullable(),
});

/* ===================== SELECT PARA PRISMA ===================== */

/**
 * Select estándar para obtener los datos base de un conjunto
 * sin incluir relaciones (inventario, operarios, etc.)
 */
export const conjuntoPublicSelect = {
  nit: true,
  nombre: true,
  direccion: true,
  correo: true,
  administradorId: true,
  empresaId: true,
} as const;

/** Helper para castear el resultado Prisma al tipo público */
export function toConjuntoPublico<T extends Record<keyof typeof conjuntoPublicSelect, any>>(
  row: T
): ConjuntoPublico {
  return row;
}
