// src/controller/JefeOperacionesController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { JefeOperacionesService } from "../services/JefeOperacionesService";

const IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

const ListarPendientesQuerySchema = z.object({
  conjuntoId: z.string().optional(),
});

const VeredictoBodySchema = z.object({
  accion: z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
  observacionesRechazo: z.string().min(3).max(500).optional(),
  fechaVerificacion: z.coerce.date().optional(),
});

/**
 * ✅ Lee empresaId desde:
 * - req.user.empresaId (si ya existe)
 * - header x-empresa-id (para Flutter)
 *
 * Devuelve number o null (si no se puede)
 */
function getEmpresaIdFromReq(req: any): number | null {
  const raw = req.user?.empresaId ?? req.headers["x-empresa-id"];
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return n;
}

export class JefeOperacionesController {
  // GET /jefe-operaciones/tareas/pendientes?conjuntoId=...
  listarPendientes: RequestHandler = async (req, res, next) => {
    try {
      const query = ListarPendientesQuerySchema.parse(req.query ?? {});
      const empresaId = getEmpresaIdFromReq(req);

      const svc = new JefeOperacionesService(prisma, empresaId);
      const rows = await svc.listarPendientes(query.conjuntoId);

      // Flutter espera List
      res.json(rows);
    } catch (err) {
      next(err);
    }
  };

  // POST /jefe-operaciones/tareas/:id/veredicto (JSON)
  veredicto: RequestHandler = async (req, res, next) => {
    try {
      const { id: tareaId } = IdParamSchema.parse(req.params);
      const body = VeredictoBodySchema.parse(req.body ?? {});
      const empresaId = getEmpresaIdFromReq(req);

      const svc = new JefeOperacionesService(prisma, empresaId);
      const out = await svc.veredicto(tareaId, body);

      res.json(out ?? { ok: true });
    } catch (err) {
      next(err);
    }
  };

  // POST /jefe-operaciones/tareas/:id/veredicto-multipart
  veredictoMultipart: RequestHandler = async (req: any, res, next) => {
    try {
      const { id: tareaId } = IdParamSchema.parse(req.params);
      const files = (req.files ?? []) as Express.Multer.File[];
      const empresaId = getEmpresaIdFromReq(req);

      const svc = new JefeOperacionesService(prisma, empresaId);
      const out = await svc.veredictoConEvidencias(tareaId, req.body, files);

      res.json(out ?? { ok: true });
    } catch (err) {
      next(err);
    }
  };
}
