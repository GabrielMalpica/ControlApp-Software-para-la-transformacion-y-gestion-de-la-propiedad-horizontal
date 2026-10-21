// src/utils/origenesPermitidos.ts
//
// Origenes web autorizados (CORS y la renovacion de sesion por cookie). Se
// leen de CORS_ALLOWED_ORIGINS y FRONTEND_WEB_URL; fuera de produccion se
// acepta ademas localhost en cualquier puerto.

function origenesConfigurados(): Set<string> {
  return new Set(
    [...(process.env.CORS_ALLOWED_ORIGINS ?? "").split(","), process.env.FRONTEND_WEB_URL ?? ""]
      .map((origin) => origin.trim())
      .filter(Boolean)
      .map((origin) => {
        try {
          return new URL(origin).origin;
        } catch {
          return "";
        }
      })
      .filter(Boolean),
  );
}

let cache: { clave: string; origenes: Set<string> } | null = null;

function origenes(): Set<string> {
  const clave = `${process.env.CORS_ALLOWED_ORIGINS ?? ""}|${process.env.FRONTEND_WEB_URL ?? ""}`;
  if (!cache || cache.clave !== clave) cache = { clave, origenes: origenesConfigurados() };
  return cache.origenes;
}

export function esOrigenLocalDeDesarrollo(origin: string): boolean {
  if (process.env.NODE_ENV === "production") return false;
  try {
    const url = new URL(origin);
    return (
      ["http:", "https:"].includes(url.protocol) &&
      ["localhost", "127.0.0.1", "[::1]", "::1"].includes(url.hostname)
    );
  } catch {
    return false;
  }
}

export function esOrigenPermitido(origin: string): boolean {
  return origenes().has(origin) || esOrigenLocalDeDesarrollo(origin);
}
