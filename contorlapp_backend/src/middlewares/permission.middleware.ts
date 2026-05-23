import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { PermissionService } from "../services/PermissionService";

const permissionService = new PermissionService(prisma);

export function requirePermission(...permissions: string[]): RequestHandler {
  return async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      const role = req.user?.rol;

      if (!userId || !role) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const empresaId =
        req.user?.empresaId?.trim() ||
        String(req.headers["x-empresa-id"] ?? "").trim() ||
        (await permissionService.resolveEmpresaIdForUser(userId, role));

      const effective = await permissionService.getEffectivePermissionsForRole(empresaId, role);
      const allowed = permissions.some((permission) => effective.has(permission));

      if (!allowed) {
        res.status(403).json({
          message: "No autorizado para esta accion segun los permisos del rol.",
        });
        return;
      }

      next();
    } catch (error) {
      next(error);
    }
  };
}
