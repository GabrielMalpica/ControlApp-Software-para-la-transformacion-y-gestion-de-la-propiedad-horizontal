import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { SupervisorService } from "../services/SupervisorServices";

// Params
const IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
});

// Query filtros (ajústalo si tu service espera otros nombres)
const ListarSchema = z.object({
  conjuntoId: z.string().optional(),
  operarioId: z.coerce.string().optional(), // si viene string, tu service decide si lo parsea
  estado: z.string().optional(),
  desde: z.string().optional(),
  hasta: z.string().optional(),
  borrador: z
    .union([z.literal("true"), z.literal("false")])
    .optional()
    .transform((v) => (v == null ? undefined : v === "true")),
});

function getSupervisorIdFromReq(req: any): string {
  // ✅ TU AUTH GUARDA EL ID EN sub
  const sid = req.user?.sub;
  if (!sid) throw new Error("No se pudo identificar supervisorId en el token.");
  return String(sid);
}

export class SupervisorController {
  // GET /supervisor/tareas
  listarTareas: RequestHandler = async (req, res, next) => {
    try {
      const supervisorId = getSupervisorIdFromReq(req);
      const svc = new SupervisorService(prisma, supervisorId);

      const q = ListarSchema.parse(req.query);

      const payload = {
        conjuntoId: q.conjuntoId,
        operarioId: q.operarioId, // si quieres, conviértelo aquí
        estado: q.estado,
        desde: q.desde,
        hasta: q.hasta,
        borrador: q.borrador,
      };

      const data = await svc.listarTareas(payload);
      res.json(data);
    } catch (err) {
      next(err);
    }
  };

  cronogramaImprimible: RequestHandler = async (req, res, next) => {
    try {
      const supervisorId = String(
        (req as any).user?.id ?? req.headers["x-user-id"] ?? "",
      );
      // ajusta a tu auth real

      const conjuntoId = String(req.query.conjuntoId ?? "");
      const operarioId = String(req.query.operarioId ?? "");
      const desde = req.query.desde
        ? new Date(String(req.query.desde))
        : undefined;
      const hasta = req.query.hasta
        ? new Date(String(req.query.hasta))
        : undefined;

      if (!conjuntoId || !operarioId || !desde || !hasta) {
        res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
        return;
      }

      const svc = new SupervisorService(prisma, supervisorId);
      const r = await svc.cronogramaImprimible({
        conjuntoId,
        operarioId,
        desde,
        hasta,
      });
      res.json(r);
    } catch (err) {
      next(err);
    }
  };

  // POST /supervisor/tareas/:id/cerrar
  cerrarTarea: RequestHandler = async (req, res, next) => {
    try {
      const supervisorId = getSupervisorIdFromReq(req);
      const svc = new SupervisorService(prisma, supervisorId);

      const tareaId = Number(req.params.id);
      if (!Number.isFinite(tareaId) || tareaId <= 0) {
        res.status(400).json({ error: "id inválido" });
        return;
      }

      const files = (req.files as Express.Multer.File[]) ?? [];

      await svc.cerrarTareaConEvidencias(
        tareaId,
        {
          // body viene como strings en multipart
          observaciones: req.body.observaciones,
          fechaFinalizarTarea: req.body.fechaFinalizarTarea,
          insumosUsados: req.body.insumosUsados,
        },
        files,
      );

      res.json({ ok: true });
    } catch (e) {
      next(e);
    }
  };

  // POST /supervisor/tareas/:id/veredicto
  veredicto: RequestHandler = async (req, res, next) => {
    try {
      const supervisorId = getSupervisorIdFromReq(req);
      const svc = new SupervisorService(prisma, supervisorId);

      const { id } = IdParamSchema.parse(req.params);
      await svc.veredicto(id, req.body);

      res.json({ ok: true });
    } catch (err) {
      next(err);
    }
  };
}
