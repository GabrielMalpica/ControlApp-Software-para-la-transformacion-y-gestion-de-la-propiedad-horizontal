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

/* ---------------------------- tokens de renovacion ---------------------------- */

/**
 * `web`: cookie HttpOnly, ventanas cortas. `app`: la app Android guarda el
 * token en almacenamiento seguro y lo usa al volver a tener senal, que puede
 * ser dias despues (operarios sin internet en el conjunto).
 */
export type CanalSesion = "web" | "app";

function canalDe(valor: unknown): CanalSesion {
  return valor === "app" ? "app" : "web";
}

function limitar(valor: number, min: number, max: number, porDefecto: number): number {
  return Number.isFinite(valor) ? Math.min(Math.max(valor, min), max) : porDefecto;
}

/** Sin usar la sesion durante este tiempo, el token de renovacion deja de servir. */
export function inactividadMs(canal: CanalSesion = "web"): number {
  if (canal === "app") {
    return limitar(Number(process.env.SESION_APP_INACTIVIDAD_DIAS ?? 30), 1, 90, 30) * 86_400_000;
  }
  return limitar(Number(process.env.SESION_WEB_INACTIVIDAD_HORAS ?? 24), 1, 168, 24) * 3_600_000;
}

/** Vida maxima de una sesion, se use o no: luego hay que iniciar sesion. */
export function vidaMaximaMs(canal: CanalSesion = "web"): number {
  if (canal === "app") {
    return limitar(Number(process.env.SESION_APP_MAX_DIAS ?? 90), 1, 365, 90) * 86_400_000;
  }
  return limitar(Number(process.env.SESION_WEB_MAX_DIAS ?? 7), 1, 30, 7) * 86_400_000;
}

/**
 * Dos pestanas pueden renovar a la vez con la misma cookie. Si el token se
 * acaba de usar, no se trata como robo: se pide reintentar (el navegador ya
 * tendra la cookie nueva).
 */
const GRACIA_REUSO_MS = 30_000;

/**
 * App movil con senal mala: el servidor rota el token pero la respuesta no
 * llega y la app vuelve a presentar el anterior. Si el sucesor nunca se uso,
 * no es robo sino una respuesta perdida: se reemplaza el sucesor por uno nuevo
 * en vez de cerrar la sesion (solo durante este tiempo y solo en la app).
 */
const RECUPERACION_RESPUESTA_PERDIDA_MS = 10 * 60_000;

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
  datos: {
    usuarioId: string;
    versionSesion: number;
    userAgent?: string | null;
    canal?: CanalSesion;
  },
): Promise<SesionRefreshEmitida> {
  const canal = canalDe(datos.canal);
  const ahora = Date.now();
  const familiaExpiraEn = new Date(ahora + vidaMaximaMs(canal));
  const expiraEn = new Date(Math.min(ahora + inactividadMs(canal), familiaExpiraEn.getTime()));
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
      canal,
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
  canalEsperado?: CanalSesion,
): Promise<{ usuarioId: string } & SesionRefreshEmitida> {
  const fila = await db.sesionRefresh.findUnique({
    where: { tokenHash: hashToken(tokenPlano) },
    include: { usuario: { select: { activo: true, versionSesion: true } } },
  });
  if (!fila || fila.revocadoEn) throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");

  // Un token de la web no sirve en la ruta de la app ni al reves: cada canal
  // tiene sus ventanas y su forma de transporte (cookie vs. cuerpo).
  const canal = canalDe((fila as { canal?: unknown }).canal);
  if (canalEsperado && canal !== canalEsperado) {
    throw httpError(401, SESION_NO_VALIDA, "SESION_INVALIDA");
  }

  const ahora = Date.now();
  if (fila.usadoEn) {
    const desdeUso = ahora - fila.usadoEn.getTime();
    if (desdeUso <= GRACIA_REUSO_MS) {
      throw httpError(409, "La sesión se está renovando. Intenta de nuevo.", "RENOVACION_EN_CURSO");
    }
    if (canal === "app" && desdeUso <= RECUPERACION_RESPUESTA_PERDIDA_MS) {
      const recuperado = await recuperarRespuestaPerdida(db, fila, ahora, userAgent);
      if (recuperado) return recuperado;
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
  const expiraEn = new Date(Math.min(ahora + inactividadMs(canal), fila.familiaExpiraEn.getTime()));
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
        canal,
      },
    });
  });

  return { usuarioId: fila.usuarioId, token, expiraEn };
}

/**
 * Ver RECUPERACION_RESPUESTA_PERDIDA_MS. Devuelve null si el sucesor ya se uso
 * (entonces si es un reuso y la familia se revoca).
 */
async function recuperarRespuestaPerdida(
  db: PrismaClient,
  fila: {
    familiaId: string;
    usuarioId: string;
    versionSesion: number;
    familiaExpiraEn: Date;
    usadoEn: Date | null;
    usuario: { activo: boolean; versionSesion: number };
  },
  ahora: number,
  userAgent?: string | null,
): Promise<({ usuarioId: string } & SesionRefreshEmitida) | null> {
  if (!fila.usadoEn) return null;
  if (fila.familiaExpiraEn.getTime() <= ahora) return null;
  if (!fila.usuario.activo || fila.versionSesion !== fila.usuario.versionSesion) return null;

  const sucesor = await db.sesionRefresh.findFirst({
    where: {
      familiaId: fila.familiaId,
      usadoEn: null,
      revocadoEn: null,
      creadoEn: { gte: fila.usadoEn },
    },
    orderBy: { creadoEn: "desc" },
    select: { id: true },
  });
  if (!sucesor) return null;

  const token = generarToken();
  const expiraEn = new Date(Math.min(ahora + inactividadMs("app"), fila.familiaExpiraEn.getTime()));
  const reemplazado = await db.$transaction(async (tx) => {
    const anulado = await tx.sesionRefresh.updateMany({
      where: { id: sucesor.id, usadoEn: null, revocadoEn: null },
      data: { revocadoEn: new Date(ahora), motivoRevocacion: "RESPUESTA_PERDIDA" },
    });
    if (anulado.count !== 1) return false;
    await tx.sesionRefresh.create({
      data: {
        familiaId: fila.familiaId,
        usuarioId: fila.usuarioId,
        tokenHash: hashToken(token),
        versionSesion: fila.versionSesion,
        expiraEn,
        familiaExpiraEn: fila.familiaExpiraEn,
        userAgent: recortarUserAgent(userAgent),
        canal: "app",
      },
    });
    return true;
  });
  if (!reemplazado) {
    throw httpError(409, "La sesión se está renovando. Intenta de nuevo.", "RENOVACION_EN_CURSO");
  }
  return { usuarioId: fila.usuarioId, token, expiraEn };
}

/** Cierra la sesion asociada a un token de renovacion (logout). Silencioso si no existe. */
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
