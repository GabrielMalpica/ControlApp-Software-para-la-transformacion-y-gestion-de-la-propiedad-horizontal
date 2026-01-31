import { RequestHandler } from "express";
import jwt from "jsonwebtoken";

export type AuthPayload = {
  sub: string;
  rol: string;
  correo: string;
  iat?: number;
  exp?: number;
};

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
    }
  }
}

export const authRequired: RequestHandler = (req, res, next) => {
  const header = req.headers.authorization;

  if (!header || !header.startsWith("Bearer ")) {
    res.status(401).json({ message: "Token requerido" });
    return;
  }

  const token = header.replace("Bearer ", "").trim();

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET as string) as AuthPayload;
    req.user = payload;
    next();
  } catch {
    res.status(401).json({ message: "Token inválido o expirado" });
  }
};
