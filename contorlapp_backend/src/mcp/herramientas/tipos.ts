// src/mcp/herramientas/tipos.ts
//
// Contrato de una herramienta MCP de ControlApp. Ver
// docs/mcp/MCP_INTEGRATION_GUIDELINES.md: cada herramienta declara modulo,
// scope, riesgo y version, valida su entrada con zod `.strict()` y solo
// llama a casos de uso de src/aplicacion (nunca a Prisma ni a services).
import type { PrismaClient } from "@prisma/client";
import type { z } from "zod";

import type { ContextoAccion } from "../../aplicacion/contexto";
import type { Referencias } from "../referencias";

export type NivelRiesgo = "LECTURA" | "ESCRITURA" | "ALTO_RIESGO";

export type ContextoHerramienta = {
  prisma: PrismaClient;
  accion: ContextoAccion;
  conexionId: string;
  clienteId: string;
  clienteNombre: string;
  /** Scopes efectivos (concedidos y vigentes en la conexion), ya expandidos. */
  scopes: Set<string>;
  refs: Referencias;
  ip: string | null;
  userAgent: string | null;
};

export type ResultadoHerramienta = {
  datos: unknown;
  resultado?: "OK" | "PREVIEW" | "CONFIRMADO";
  entidades?: Array<{ tipo: string; id: string | number }>;
  confirmacionId?: string;
};

export type DefinicionHerramienta<S extends z.ZodObject<any> = z.ZodObject<any>> = {
  nombre: string;
  titulo: string;
  descripcion: string;
  modulo: string;
  version: number;
  scope: string;
  riesgo: NivelRiesgo;
  entrada: S;
  /** Pistas para el cliente (MCP tool annotations). */
  destructiva?: boolean;
  idempotente?: boolean;
  ejecutar: (ctx: ContextoHerramienta, args: z.infer<S>) => Promise<ResultadoHerramienta>;
};

export function definirHerramienta<S extends z.ZodObject<any>>(def: DefinicionHerramienta<S>): DefinicionHerramienta<S> {
  return def;
}
