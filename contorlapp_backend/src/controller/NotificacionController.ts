import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { NotificacionService } from "../services/NotificacionService";

const ListarQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).optional(),
  soloNoLeidas: z
    .string()
    .optional()
    .transform((v) => v === "true"),
});

const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

const service = new NotificacionService(prisma);

function getUsuarioAutenticado(req: any): string | null {
  const id = req.user?.sub;
  if (!id) return null;
  return String(id);
}

export class NotificacionController {
  listar: RequestHandler = async (req, res, next) => {
    try {
      const usuarioId = getUsuarioAutenticado(req);
      if (!usuarioId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const q = ListarQuery.parse(req.query ?? {});
      const items = await service.listarUsuario(usuarioId, {
        limit: q.limit,
        soloNoLeidas: q.soloNoLeidas,
      });
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  contarNoLeidas: RequestHandler = async (req, res, next) => {
    try {
      const usuarioId = getUsuarioAutenticado(req);
      if (!usuarioId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const total = await service.contarNoLeidas(usuarioId);
      res.json({ total });
    } catch (err) {
      next(err);
    }
  };

  marcarLeida: RequestHandler = async (req, res, next) => {
    try {
      const usuarioId = getUsuarioAutenticado(req);
      if (!usuarioId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { id } = IdParam.parse(req.params);
      const ok = await service.marcarLeida(usuarioId, id);
      if (!ok) {
        res.status(404).json({ message: "Notificacion no encontrada" });
        return;
      }

      const total = await service.contarNoLeidas(usuarioId);
      res.json({ ok: true, totalNoLeidas: total });
    } catch (err) {
      next(err);
    }
  };

  marcarTodasLeidas: RequestHandler = async (req, res, next) => {
    try {
      const usuarioId = getUsuarioAutenticado(req);
      if (!usuarioId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const actualizadas = await service.marcarTodasLeidas(usuarioId);
      res.json({ ok: true, actualizadas, totalNoLeidas: 0 });
    } catch (err) {
      next(err);
    }
  };
}
