// src/aplicacion/contexto.ts
//
// Quien actua en un caso de uso. Lo arma cada entrada (la API REST desde el
// JWT, el MCP desde su access token) con la empresa resuelta en la BD, nunca
// con datos del cliente. Los casos de uso de esta carpeta no dependen de
// Express: asi el MCP aplica exactamente las mismas reglas que la app.
import type { ActorAuditoria } from "../model/Auditoria";

export type CanalAccion = "WEB" | "MCP";

export type ContextoAccion = {
  actor: { id: string; rol: string; nombre: string | null };
  empresaId: string;
  canal: CanalAccion;
};

export function actorAuditoria(ctx: ContextoAccion): ActorAuditoria {
  return { id: ctx.actor.id, rol: ctx.actor.rol, nombre: ctx.actor.nombre };
}

type HttpError = Error & { status: number; code?: string };

export function errorAplicacion(status: number, mensaje: string, codigo?: string): HttpError {
  const error = new Error(mensaje) as HttpError;
  error.status = status;
  if (codigo) error.code = codigo;
  return error;
}

/** Recurso ajeno o inexistente: 404 sin distinguir (no se revela que existe). */
export function noEncontrado(mensaje = "Recurso no encontrado"): HttpError {
  return errorAplicacion(404, mensaje, "NO_ENCONTRADO");
}
