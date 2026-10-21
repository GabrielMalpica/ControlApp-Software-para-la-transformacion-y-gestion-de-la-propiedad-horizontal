// src/mcp/errores.ts
//
// Traduce cualquier error de un caso de uso a un resultado de herramienta con
// codigo estable y mensaje legible, sin filtrar detalles tecnicos (SQL, stack,
// nombres de variables). Mismo criterio que el manejador central de la API.
import { Prisma } from "@prisma/client";
import { ZodError } from "zod";

export type ErrorHerramienta = { codigo: string; mensaje: string; status: number };

const PATRONES_TECNICOS = [
  /cannot\s+(read|set|convert|destructure)/i,
  /\bundefined\b/i,
  /\bnull\b/i,
  /\bprisma\b/i,
  /\b(Type|Reference|Syntax|Range)Error\b/i,
  /\bE(NOENT|CONN|TIMEDOUT|ADDR)/i,
  /_SECRET|_KEY|DATABASE_URL/i,
  /\s+at\s+.+\(.+\)/,
  /unexpected token/i,
  /invalid `.*` invocation/i,
];

/** Quita los prefijos con mojibake que traen algunos mensajes viejos ("Ã¢ÂÅ’ ..."). */
function limpiar(mensaje: string): string {
  return mensaje
    // "Ã"/"Â" seguidos de caracteres Latin-1 o de puntuacion: UTF-8 leido como
    // Windows-1252 (p. ej. "Ã¢ÂÅ’ " era un emoji).
    .replace(/[ÃÂ][ -ÿŒ-ƒˆ-˜‐-™]+\s*/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 600);
}

function esSeguro(mensaje: string): boolean {
  return Boolean(mensaje) && !PATRONES_TECNICOS.some((p) => p.test(mensaje));
}

function statusPorMensaje(mensaje: string): number {
  const m = mensaje.toLowerCase();
  if (m.includes("no autorizado")) return 403;
  if (m.includes("no encontrad") || m.includes("no existe")) return 404;
  if (m.includes("ya existe") || m.includes("ya est")) return 409;
  return 400;
}

const CODIGO_POR_STATUS: Record<number, string> = {
  400: "VALIDACION",
  401: "NO_AUTENTICADO",
  403: "DENEGADO",
  404: "NO_ENCONTRADO",
  409: "CONFLICTO",
  410: "NO_DISPONIBLE",
  429: "LIMITE",
};

export function traducirError(err: unknown): ErrorHerramienta {
  if (err instanceof ZodError) {
    const issue = err.issues[0];
    return {
      status: 400,
      codigo: "VALIDACION",
      mensaje: `Dato inválido en ${issue?.path?.join(".") || "la solicitud"}: ${issue?.message ?? "revisa los datos"}.`,
    };
  }
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    if (err.code === "P2002") return { status: 409, codigo: "CONFLICTO", mensaje: "Ya existe un registro con esos datos." };
    if (err.code === "P2025") return { status: 404, codigo: "NO_ENCONTRADO", mensaje: "El registro ya no existe." };
    return { status: 500, codigo: "ERROR_INTERNO", mensaje: "Ocurrió un error técnico. Intenta de nuevo más tarde." };
  }
  const e = err as { status?: unknown; code?: unknown; message?: unknown };
  const mensaje = limpiar(String(e?.message ?? ""));
  const status = typeof e?.status === "number" ? e.status : esSeguro(mensaje) ? statusPorMensaje(mensaje) : 500;
  if (status >= 500 || !esSeguro(mensaje)) {
    return { status: 500, codigo: "ERROR_INTERNO", mensaje: "Ocurrió un error inesperado. Intenta de nuevo más tarde." };
  }
  // Los codigos de negocio ("TAREAS_ABIERTAS", "ESTADO_CAMBIO"...) se conservan.
  const codigo =
    typeof e?.code === "string" && /^[A-Z_]{3,40}$/.test(e.code) ? e.code : CODIGO_POR_STATUS[status] ?? "ERROR";
  return { status, codigo, mensaje };
}
