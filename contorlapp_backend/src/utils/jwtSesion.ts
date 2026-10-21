// src/utils/jwtSesion.ts
//
// Firma y verificacion del JWT de sesion de ControlApp. Un solo lugar fija el
// algoritmo, el emisor y la audiencia: asi un token emitido para otro
// servicio (por ejemplo el futuro MCP, que usara otra clave y otra audiencia)
// nunca se acepta en la API, y viceversa.
import { randomUUID } from "crypto";
import jwt from "jsonwebtoken";

export const JWT_EMISOR = "controlapp-api";
export const JWT_AUDIENCIA = "controlapp-api";
const ALGORITMO = "HS256" as const;

/** App movil: el token vive en almacenamiento seguro del dispositivo. */
export const DURACION_TOKEN_APP_SEG = 8 * 60 * 60;

/**
 * Web: el token vive solo en memoria y se renueva con la cookie HttpOnly de
 * `/auth/refresh`. Configurable para despliegues donde la cookie todavia no
 * puede viajar (API en otro sitio que el frontend).
 */
export function duracionTokenWebSeg(): number {
  const minutos = Number(process.env.JWT_WEB_MINUTOS ?? 15);
  if (!Number.isFinite(minutos)) return 15 * 60;
  return Math.round(Math.min(Math.max(minutos, 5), 8 * 60) * 60);
}

export type AuthPayload = {
  sub: string;
  rol: string;
  correo: string;
  empresaId?: string;
  /** Version de sesion del usuario al emitir el token (ver Usuario.versionSesion). */
  sv?: number;
  jti?: string;
  iat?: number;
  exp?: number;
};

type HttpError = Error & { status: number };

function secreto(): string {
  const valor = process.env.JWT_SECRET;
  if (!valor) {
    const error = new Error("JWT_SECRET no está configurado") as HttpError;
    error.status = 500;
    throw error;
  }
  return valor;
}

export function firmarTokenSesion(
  datos: {
    usuarioId: string;
    rol: string;
    correo: string;
    empresaId?: string | null;
    versionSesion: number;
  },
  duracionSeg: number,
): { token: string; jti: string; expiraEn: Date } {
  const jti = randomUUID();
  const token = jwt.sign(
    {
      sub: datos.usuarioId,
      rol: datos.rol,
      correo: datos.correo,
      empresaId: datos.empresaId || undefined,
      sv: datos.versionSesion,
    },
    secreto(),
    {
      algorithm: ALGORITMO,
      expiresIn: duracionSeg,
      jwtid: jti,
      issuer: JWT_EMISOR,
      audience: JWT_AUDIENCIA,
    },
  );
  return { token, jti, expiraEn: new Date(Date.now() + duracionSeg * 1_000) };
}

/** Lanza si la firma, el algoritmo, el emisor, la audiencia o la fecha no son validos. */
export function verificarTokenSesion(token: string): AuthPayload {
  const payload = jwt.verify(token, secreto(), {
    algorithms: [ALGORITMO],
    issuer: JWT_EMISOR,
    audience: JWT_AUDIENCIA,
  });
  if (
    typeof payload === "string" ||
    typeof payload.sub !== "string" ||
    !payload.sub ||
    typeof (payload as { rol?: unknown }).rol !== "string"
  ) {
    throw new Error("Token inválido");
  }
  return payload as AuthPayload;
}
