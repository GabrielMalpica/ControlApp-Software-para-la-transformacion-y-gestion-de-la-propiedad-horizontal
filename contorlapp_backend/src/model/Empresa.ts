// src/models/empresa.ts
import { z } from "zod";

/** Dominio base 1:1 con el modelo Prisma (sin relaciones) */
export interface EmpresaDominio {
  id: number;
  nombre: string;
  nit: string;
  limiteHorasSemana: number; // NUEVO
}

/** Tipo público (idéntico, sin relaciones) */
export type EmpresaPublica = EmpresaDominio;

/* ===================== DTOs ===================== */

/** Crear empresa */
export const CrearEmpresaDTO = z.object({
  nombre: z.string().min(3),
  nit: z.string().min(3),
  // opcional: si no lo envías, aplica el default de Prisma (46)
  limiteHorasSemana: z.coerce.number().int().min(1).max(84).optional(),
});

/** Editar empresa */
export const EditarEmpresaDTO = z.object({
  nombre: z.string().min(3).optional(),
  nit: z.string().min(3).optional(), // normalmente no se cambia
  limiteHorasSemana: z.coerce.number().int().min(1).max(84).optional(), // NUEVO
});

/** Filtro de búsqueda de empresas */
export const FiltroEmpresaDTO = z.object({
  nit: z.string().optional(),
  nombre: z.string().optional(),
});

/* ===================== SELECT BASE PARA PRISMA ===================== */
export const empresaPublicSelect = {
  id: true,
  nombre: true,
  nit: true,
  limiteHorasSemana: true, // NUEVO
} as const;

/** Helper para castear el resultado de Prisma al tipo público */
export function toEmpresaPublica<
  T extends Record<keyof typeof empresaPublicSelect, any>
>(row: T): EmpresaPublica {
  return row as unknown as EmpresaPublica;
}
