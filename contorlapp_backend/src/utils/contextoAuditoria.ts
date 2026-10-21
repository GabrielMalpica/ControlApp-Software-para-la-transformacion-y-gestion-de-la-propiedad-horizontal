// src/utils/contextoAuditoria.ts
//
// Origen de la accion que se esta ejecutando (p. ej. una herramienta del MCP).
// AuditoriaService lo lee al escribir cada evento: asi todo lo que audita un
// servicio de dominio durante una herramienta queda marcado como MCP, con la
// conexion y la herramienta, sin pasar el dato por cada servicio.
import { AsyncLocalStorage } from "async_hooks";

export type ContextoOrigenAuditoria = {
  origen: string;
  metadata: Record<string, unknown>;
};

const almacen = new AsyncLocalStorage<ContextoOrigenAuditoria>();

export function ejecutarConOrigenAuditoria<T>(
  contexto: ContextoOrigenAuditoria,
  fn: () => Promise<T>,
): Promise<T> {
  return almacen.run(contexto, fn);
}

export function origenAuditoriaActual(): ContextoOrigenAuditoria | undefined {
  return almacen.getStore();
}
