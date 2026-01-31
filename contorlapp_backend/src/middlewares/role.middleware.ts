import { RequestHandler } from "express";

export function requireRoles(...roles: string[]): RequestHandler {
  return (req, res, next) => {
    const rol = req.user?.rol;
    if (!rol) {
      res.status(401).json({ message: "No autenticado" });
      return;
    }

    if (!roles.includes(rol)) {
      res.status(403).json({ message: "No autorizado para este recurso" });
      return;
    }

    next();
  };
}
