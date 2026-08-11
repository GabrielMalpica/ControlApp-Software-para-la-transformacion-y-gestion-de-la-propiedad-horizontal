import { RequestHandler } from "express";
import jwt from "jsonwebtoken";
import { isTokenRevoked } from "../services/RedisService";

export type AuthPayload = {
  sub: string;
  rol: string;
  correo: string;
  empresaId?: string;
  jti?: string;
  iat?: number;
  exp?: number;
};

function isPublicRequest(method: string, path: string): boolean {
  if (method === "GET" && (path === "/" || path === "/ping")) return true;
  if (
    method === "POST" &&
    (path === "/auth/login" || path === "/auth/recuperar-contrasena")
  ) {
    return true;
  }

  return (
    method === "GET" &&
    (path === "/commerce/catalogo" || path.startsWith("/commerce/catalogo/"))
  );
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
    }
  }
}

export const authRequired: RequestHandler = async (req, res, next) => {
  const header = req.headers.authorization;

  if (!header || !header.startsWith("Bearer ")) {
    res.status(401).json({ message: "Token requerido" });
    return;
  }

  const token = header.replace("Bearer ", "").trim();

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET as string) as AuthPayload;
    if (payload.jti && (await isTokenRevoked(payload.jti))) {
      res.status(401).json({ message: "Token revocado" });
      return;
    }
    req.user = payload;
    next();
  } catch {
    res.status(401).json({ message: "Token inválido o expirado" });
  }
};

export const authOptional: RequestHandler = async (req, _res, next) => {
  if (req.user) {
    next();
    return;
  }

  const header = req.headers.authorization;

  if (!header || !header.startsWith("Bearer ")) {
    next();
    return;
  }

  const token = header.replace("Bearer ", "").trim();

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET as string) as AuthPayload;
    req.user = payload.jti && (await isTokenRevoked(payload.jti)) ? undefined : payload;
  } catch {
    req.user = undefined;
  }

  next();
};

/**
 * Cierre defensivo global. Las rutas siguen declarando autorizacion por rol y
 * permiso; esta allowlist evita que una ruta nueva quede publica por omision.
 */
export const authRequiredUnlessPublic: RequestHandler = (req, res, next) => {
  if (isPublicRequest(req.method.toUpperCase(), req.path)) {
    next();
    return;
  }

  authRequired(req, res, next);
};
