// src/models/gerente.ts
import { z } from "zod";
import { Rol } from "@prisma/client";

/** Tipo base para el ID (mismo que Usuario.id) */
export type GerenteId = number;

/** Dominio 1:1 con Prisma */
export interface GerenteDominio {
  id: GerenteId;
  empresaId?: string | null; // referencia opcional al nit de Empresa
}

/** Tipo público — idéntico por ahora */
export type GerentePublico = GerenteDominio;

export const UsuarioIdParam = z.object({
  id: z.string().min(1, "El id de usuario (cédula) es obligatorio"),
});

/* ===================== DTOs ===================== */

/**
 * Crear gerente: requiere que ya exista el Usuario con ese id
 * y opcionalmente se asocie a una Empresa.
 */
export const CrearGerenteDTO = z.object({
  Id: z.string().min(1, "El id (cédula) del usuario es obligatorio"),
  empresaId: z.string().min(3).optional(),
});

/** Editar gerente (solo empresa por ahora) */
export const EditarGerenteDTO = z.object({
  empresaId: z.string().min(3).optional().nullable(),
});

/* ===================== SELECT PARA PRISMA ===================== */
export const gerentePublicSelect = {
  id: true,
  empresaId: true,
} as const;

/** Helper para castear resultado Prisma al tipo público */
export function toGerentePublico<
  T extends Record<keyof typeof gerentePublicSelect, any>
>(row: T): GerentePublico {
  return row;
}

export const ListarUsuariosDTO = z.object({
  // ?rol=operario | administrador | jefe_operaciones | supervisor | gerente
  rol: z.nativeEnum(Rol).optional(),
});

export type ListarUsuariosInput = z.infer<typeof ListarUsuariosDTO>;