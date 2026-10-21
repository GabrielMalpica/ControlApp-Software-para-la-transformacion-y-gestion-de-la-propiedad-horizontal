// src/services/SesionService.ts
//
// Estado de sesion del lado del servidor. El JWT ya no es la unica fuente de
// verdad: cada peticion contrasta el token con el usuario en BD (activo, rol,
// version de sesion, cambio de contrasena pendiente), con un cache corto para
// no pagar una consulta por peticion. Ademas guarda los tokens de renovacion
// rotativos de la sesion web (cookie HttpOnly).
import { createHash, randomBytes, randomUUID } from "crypto";
import type { Prisma, PrismaClient } from "@prisma/client";

import { cached, cacheDelete } from "./RedisService";

type Db = PrismaClient | Prisma.TransactionClient;
type HttpError = Error & { status: number; code?: string };

function httpError(status: number, message: string, code?: string): HttpError {
  const error = new Error(message) as HttpError;
  error.status = status;
  if (code) error.code = code;
  return error;
}

/* ------------------------------ estado por usuario ------------------------------ */

export type EstadoSesion = {
  activo: boolean;
  rol: string;
  versionSesion: number;
  requiereCambioContrasena: boolean;
};

/**
 * Un cambio de rol, una desactivacion o un "cerrar todas las sesiones" tarda
 * como mucho esto en surtir efecto aunque quien lo haga no invalide el cache.
 */
const TTL_ESTADO_SEG = 30;
const claveEstado = (usuarioId: string) => `sesion:estado:v1:${usuarioId}`;

export async function estadoSesionUsuario(
  db: Db,
  usuarioId: string,
): Promise<EstadoSesion | null> {
  return cached(claveEstado(usuarioId), TTL_ESTADO_SEG, async () => {
    const usuario = await db.usuario.findUnique({
      where: { id: usuarioId },
      select: { activo: true, rol: true, versionSesion: true, requiereCambioContrasena: true },
    });
    return usuario
      ? {
          activo: usuario.activo,
          rol: String(usuario.rol).trim().toLowerCase(),
          versionSesion: usuario.versionSesion,
          requiereCambioContrasena: usuario.requiereCambioContrasena,
        }
      : null;
  });
}

export async function invalidarEstadoSesion(usuarioId: string): Promise<void> {
  await cacheDelete(claveEstado(usuarioId));
}

/**
 * Motivo por el que un token valido criptograficamente ya no representa una
 * sesion vigente, o null si sigue vigente.
 */
export function motivoSesionInvalida(
  token: { rol: string; sv?: number },
  estado: EstadoSesion | null,
): string | null {
  if (!estado) return "La cuenta ya no existe.";
  if (!estado.activo) return "Tu usuario está inactivo. Comunícate con tu gerente.";
  if (String(token.rol).trim().toLowerCase() !== estado.rol) {
    return "Tu rol cambió. Inicia sesión de nuevo.";
  }
  if ((token.sv ?? 0) !== estado.versionSesion) {
    return "Tu sesión se cerró. Inicia sesión de nuevo.";
  }
  return null;
}

/* --------------------------- tokens de renovacion (web) -------------------------- */

function limitar(valor: number, min: number, max: number, porDefecto: number): number {
  return Number.isFinite(valor) ? Math.min(Math.max(valor, min), max) : porDefecto;
}

/** Sin usar la sesion durante este tiempo, la cookie deja de servir. */
function inactividadMs(): number {
  return limitar(Number(process.env.SESION_WEB_INACTIVIDAD_HORAS ?? 24), 1, 168, 24) * 3_600_000;
}

/** Vida maxima de una sesion web, se use o no: luego hay que iniciar sesion. */
function vidaMaximaMs(): number {
  return limitar(Number(process.env.SESION_WEB_MAX_DIAS ?? 7), 1, 30, 7) * 86_400_000;
}

/**
 * Dos pestanas pueden renovar a la vez con la misma cookie. Si el token se
 * acaba de usar, no se trata como robo: se pide reintentar (el navegador ya
 * tendra la cookie nueva).
 */
const GRACIA_REUSO_MS = 30_000;

export function hashToken(tokenPlano: string): string {
  return createHash("sha256").update(tokenPlano).digest("hex");
}

function generarToken(): string {
  return randomBytes(32).toString("base64url");
}

function recortarUserAgent(userAgent?: string | null): string | null {
  const valor = String(userAgent ?? "").trim();
  return valor ? valor.slice(0, 300) : null;
}

export type SesionRefreshEmitida = { token: string; expiraEn: Date };

export async function crearSesionRefresh(
  db: Db,
  datos: { usuarioId: string; versionSesion: number; userAgent?: string | null },
): Promise<SesionRefreshEmitida> {
  const ahora = Date.now();
  const familiaExpiraEn = new Date(ahora + vidaMaximaMs());
  const expiraEn = new Date(Math.min(ahora + inactividadMs(), familiaExpiraEn.getTime()));
  const token = generarToken();

  // Limpieza oportunista: las familias vencidas de este usuario ya no sirven.
  await db.sesionRefresh.deleteMany({
    where: { usuarioId: datos.usuarioId, familiaExpiraEn: { lt: new Date(ahora) } },
  });
  await db.sesionRefresh.create({
    data: {
      familiaId: randomUUID(),
      usuarioId: datos.usuarioId,
      tokenHash: hashToken(token),
      versionSesion: datos.versionSesion,
      expiraEn,
      familiaExpiraEn,
      userAgent: recortarUserAgent(datos.userAgent),
    },
  });
  return { token, expiraEn };
}

async function revocarFamilia(db: Db, familiaId: string, motivo: string): Promise<void> {
  await db.sesionRefresh.updateMany({
    where: { familiaId, revocadoEn: null },
    data: { revocadoEn: new Date(), motivoRevocacion: motivo },
  });
}

const SESION_NO_VALIDA = "Tu sesión expiró. Inicia sesión de nuevo.";

/**
 * Cambia un token de renovacion por otro de la misma familia. Presentar uno ya
 * usado (fuera de la ventana de gracia) revoca la familia completa: alguien
 * mas tiene una copia.
 */
export async function rotarSesionRefresh(
  db: PrismaClient,
  tokenPlano: string,
  userAgent?: string | null,
): Promise<{ usuarioId: string } & SesionRefreshEmitida> {
  const fila = await db.sesionRefresh.findUnique({
    where: { tokenHash: hashToken(tokenPlano) },
    include: { usuario: { select: { activo: true, versionSesion: true } } },
  });
  if (!fila || fila.revocadoEn) throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");

  const ahora = Date.now();
  if (fila.usadoEn) {
    if (ahora - fila.usadoEn.getTime() <= GRACIA_REUSO_MS) {
      throw httpError(409, "La sesión se está renovando. Intenta de nuevo.", "RENOVACION_EN_CURSO");
    }
    await revocarFamilia(db, fila.familiaId, "REUSO_DETECTADO");
    throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");
  }
  if (fila.expiraEn.getTime() <= ahora || fila.familiaExpiraEn.getTime() <= ahora) {
    throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");
  }
  if (!fila.usuario.activo || fila.versionSesion !== fila.usuario.versionSesion) {
    await revocarFamilia(db, fila.familiaId, "SESION_CERRADA");
    throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");
  }

  const token = generarToken();
  const expiraEn = new Date(Math.min(ahora + inactividadMs(), fila.familiaExpiraEn.getTime()));
  await db.$transaction(async (tx) => {
    // Condicional: si otra peticion lo uso entre la lectura y aqui, gana ella.
    const marcado = await tx.sesionRefresh.updateMany({
      where: { id: fila.id, usadoEn: null, revocadoEn: null },
      data: { usadoEn: new Date(ahora) },
    });
    if (marcado.count !== 1) {
      throw httpError(409, "La sesión se está renovando. Intenta de nuevo.", "RENOVACION_EN_CURSO");
    }
    await tx.sesionRefresh.create({
      data: {
        familiaId: fila.familiaId,
        usuarioId: fila.usuarioId,
        tokenHash: hashToken(token),
        versionSesion: fila.versionSesion,
        expiraEn,
        familiaExpiraEn: fila.familiaExpiraEn,
        userAgent: recortarUserAgent(userAgent),
      },
    });
  });

  return { usuarioId: fila.usuarioId, token, expiraEn };
}

/** Cierra la sesion web asociada a una cookie (logout). Silencioso si no existe. */
export async function revocarSesionRefreshPorToken(
  db: Db,
  tokenPlano: string,
  motivo: string,
): Promise<void> {
  const fila = await db.sesionRefresh.findUnique({
    where: { tokenHash: hashToken(tokenPlano) },
    select: { familiaId: true },
  });
  if (fila) await revocarFamilia(db, fila.familiaId, motivo);
}

/**
 * Cierra todas las sesiones del usuario en todos los dispositivos: sube
 * `versionSesion` (invalida todos los JWT emitidos) y revoca sus cookies de
 * renovacion. Devuelve la version nueva para emitir una sesion fresca si hace
 * falta (p. ej. tras cambiar la propia contrasena).
 */
export async function cerrarTodasLasSesiones(
  db: PrismaClient,
  usuarioId: string,
  motivo: string,
): Promise<number> {
  const actualizado = await db.$transaction(async (tx) => {
    const usuario = await tx.usuario.update({
      where: { id: usuarioId },
      data: { versionSesion: { increment: 1 } },
      select: { versionSesion: true },
    });
    await tx.sesionRefresh.updateMany({
      where: { usuarioId, revocadoEn: null },
      data: { revocadoEn: new Date(), motivoRevocacion: motivo },
    });
    return usuario;
  });
  await invalidarEstadoSesion(usuarioId);
  return actualizado.versionSesion;
}
