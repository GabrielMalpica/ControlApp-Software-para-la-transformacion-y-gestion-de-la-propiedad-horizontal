// src/controllers/AuthController.ts
import type { CookieOptions, Request, RequestHandler, Response } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import {
  AuthService,
  MENSAJE_RECUPERACION_DESACTIVADA,
  type OpcionesSesion,
  type SesionEmitida,
} from "../services/authService";
import { revokeToken } from "../services/RedisService";
import { revocarSesionRefreshPorToken } from "../services/SesionService";
import { esOrigenPermitido } from "../utils/origenesPermitidos";

const LoginSchema = z.object({
  correo: z.string().email(),
  contrasena: z.string().min(1),
  // La app web pide sesion con cookie HttpOnly de renovacion; la movil no.
  sesionWeb: z.boolean().optional(),
});

const CambiarContrasenaSchema = z.object({
  contrasenaActual: z.string().min(1),
  nuevaContrasena: z.string().min(8),
  sesionWeb: z.boolean().optional(),
});

const CambiarContrasenaInicialSchema = z.object({
  nuevaContrasena: z.string().min(8),
  sesionWeb: z.boolean().optional(),
});

const CambiarContrasenaUsuarioSchema = z.object({
  nuevaContrasena: z.string().min(8),
});

const service = new AuthService(prisma);

/* ------------------------------ cookie de sesion ------------------------------ */

const NOMBRE_COOKIE_SESION = "ca_sesion";

/**
 * La cookie solo viaja a /auth (renovar y cerrar sesion), nunca es legible
 * por JavaScript y no sirve por si sola para llamar a la API: solo cambia por
 * un token de acceso corto. Con frontend y API en el mismo sitio (p. ej.
 * app.dominio y api.dominio) basta SameSite=Lax; en sitios distintos hace
 * falta AUTH_COOKIE_SAMESITE=none (y aun asi Safari puede bloquearla).
 */
function opcionesCookie(): CookieOptions {
  const sameSiteEnv = String(process.env.AUTH_COOKIE_SAMESITE ?? "lax").trim().toLowerCase();
  const sameSite: CookieOptions["sameSite"] =
    sameSiteEnv === "none" ? "none" : sameSiteEnv === "strict" ? "strict" : "lax";
  const domain = String(process.env.AUTH_COOKIE_DOMAIN ?? "").trim() || undefined;
  return {
    httpOnly: true,
    secure:
      process.env.NODE_ENV === "production" ||
      sameSite === "none" ||
      process.env.AUTH_COOKIE_SECURE === "true",
    sameSite,
    path: "/auth",
    domain,
  };
}

function leerCookieSesion(req: Request): string | null {
  const header = req.headers.cookie;
  if (!header) return null;
  for (const parte of header.split(";")) {
    const indice = parte.indexOf("=");
    if (indice < 0) continue;
    if (parte.slice(0, indice).trim() !== NOMBRE_COOKIE_SESION) continue;
    const valor = parte.slice(indice + 1).trim();
    try {
      return decodeURIComponent(valor) || null;
    } catch {
      return null;
    }
  }
  return null;
}

function ponerCookieSesion(res: Response, refresh: { token: string; expiraEn: Date }) {
  res.cookie(NOMBRE_COOKIE_SESION, refresh.token, {
    ...opcionesCookie(),
    expires: refresh.expiraEn,
  });
}

function borrarCookieSesion(res: Response) {
  res.clearCookie(NOMBRE_COOKIE_SESION, opcionesCookie());
}

/**
 * La renovacion se autentica con una cookie, asi que es la unica ruta
 * expuesta a CSRF: ademas de SameSite exige que el origen sea el frontend.
 */
function asegurarOrigenWeb(req: Request) {
  const origin = String(req.headers.origin ?? "").trim();
  if (!origin || !esOrigenPermitido(origin)) {
    throw Object.assign(new Error("Origen no permitido."), { status: 403 });
  }
}

function opcionesSesion(req: Request, sesionWeb?: boolean): OpcionesSesion {
  return {
    sesionWeb: sesionWeb === true,
    userAgent: String(req.headers["user-agent"] ?? "") || null,
  };
}

/** Responde una sesion emitida: el token de renovacion va solo en la cookie. */
function responderSesion(res: Response, sesion: SesionEmitida, extra: Record<string, unknown> = {}) {
  if (sesion.refresh) ponerCookieSesion(res, sesion.refresh);
  res.json({
    ...extra,
    token: sesion.token,
    tokenExpiraEn: sesion.tokenExpiraEn.toISOString(),
    sesionWeb: Boolean(sesion.refresh),
    user: sesion.user,
  });
}

async function revokeCurrentToken(req: Parameters<RequestHandler>[0]) {
  const jti = req.user?.jti;
  if (!jti) return;
  const nowSeconds = Math.floor(Date.now() / 1_000);
  const ttlSeconds = Math.max(1, Number(req.user?.exp ?? nowSeconds + 8 * 60 * 60) - nowSeconds);
  await revokeToken(jti, ttlSeconds);
}

export class AuthController {
  // POST /auth/login
  login: RequestHandler = async (req, res, next) => {
    try {
      const { correo, contrasena, sesionWeb } = LoginSchema.parse(req.body);

      const sesion = await service.login(
        correo.trim().toLowerCase(),
        contrasena,
        opcionesSesion(req, sesionWeb),
      );

      responderSesion(res, sesion);
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/refresh (cookie HttpOnly; sin Bearer)
  refresh: RequestHandler = async (req, res, next) => {
    try {
      asegurarOrigenWeb(req);
      const tokenRefresh = leerCookieSesion(req);
      if (!tokenRefresh) {
        res.status(401).json({
          message: "Tu sesión expiró. Inicia sesión de nuevo.",
          code: "SESION_INVALIDA",
        });
        return;
      }

      try {
        const sesion = await service.refrescarSesionWeb(
          tokenRefresh,
          String(req.headers["user-agent"] ?? "") || null,
        );
        responderSesion(res, sesion);
      } catch (err) {
        // Una cookie que ya no sirve se borra para que el navegador no la siga
        // enviando. Una renovacion en curso en otra pestana no la invalida.
        if ((err as { code?: string })?.code !== "RENOVACION_EN_CURSO") {
          borrarCookieSesion(res);
        }
        throw err;
      }
    } catch (err) {
      next(err);
    }
  };

  // GET /auth/me
  me: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const usuario = await service.obtenerSesionUsuario(userId);
      res.json({ user: usuario });
    } catch (err) {
      next(err);
    }
  };

  perfilResumen: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const perfil = await service.obtenerResumenPerfil(userId);
      res.json(perfil);
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/cambiar-contrasena
  cambiarContrasena: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { contrasenaActual, nuevaContrasena, sesionWeb } =
        CambiarContrasenaSchema.parse(req.body);

      const sesion = await service.cambiarContrasena(
        userId,
        contrasenaActual,
        nuevaContrasena,
        opcionesSesion(req, sesionWeb),
      );

      responderSesion(res, sesion, { ok: true, message: "Contrasena actualizada correctamente" });
    } catch (err) {
      next(err);
    }
  };

  cambiarContrasenaInicial: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { nuevaContrasena, sesionWeb } = CambiarContrasenaInicialSchema.parse(req.body);

      const sesion = await service.cambiarContrasenaInicial(
        userId,
        nuevaContrasena,
        opcionesSesion(req, sesionWeb),
      );

      responderSesion(res, sesion, {
        ok: true,
        message: "Contrasena inicial actualizada correctamente",
      });
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/recuperar-contrasena
  // Desactivada: con correo + cedula cualquiera tomaba una cuenta ajena. El
  // restablecimiento lo hace un gerente o jefe (cambiarContrasenaUsuario).
  recuperarContrasena: RequestHandler = async (_req, res) => {
    res.status(410).json({
      ok: false,
      code: "RECUPERACION_DESACTIVADA",
      message: MENSAJE_RECUPERACION_DESACTIVADA,
      error: MENSAJE_RECUPERACION_DESACTIVADA,
    });
  };

  cambiarContrasenaUsuario: RequestHandler = async (req, res, next) => {
    try {
      const actorUserId = req.user?.sub;
      if (!actorUserId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const targetUserId = String(req.params.userId ?? "").trim();
      const { nuevaContrasena } = CambiarContrasenaUsuarioSchema.parse(req.body);

      const result = await service.cambiarContrasenaUsuarioPorGerente(
        actorUserId,
        targetUserId,
        nuevaContrasena,
        req.user?.empresaId ?? null,
      );

      res.json({
        ok: true,
        message: `Contrasena actualizada para ${result.nombre}. Debera cambiarla al iniciar sesion.`,
      });
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/logout (Bearer opcional: tambien cierra la cookie web)
  logout: RequestHandler = async (req, res, next) => {
    try {
      await revokeCurrentToken(req);
      const tokenRefresh = leerCookieSesion(req);
      const origin = String(req.headers.origin ?? "").trim();
      // La cookie solo se revoca desde el frontend: otra pagina no puede
      // cerrarle la sesion al usuario con un POST cruzado.
      if (tokenRefresh && origin && esOrigenPermitido(origin)) {
        await revocarSesionRefreshPorToken(prisma, tokenRefresh, "LOGOUT");
      }
      borrarCookieSesion(res);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/logout-todas: cierra la sesion en todos los dispositivos.
  logoutTodas: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      await service.cerrarTodasLasSesiones(userId);
      borrarCookieSesion(res);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
