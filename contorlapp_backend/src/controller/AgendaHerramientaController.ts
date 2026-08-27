import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { AgendaHerramientaService } from "../services/AgendaHerramientaService";

const service = new AgendaHerramientaService(prisma);

export class AgendaHerramientaController {
  private paramsFecha(req: Parameters<RequestHandler>[0]) {
    const anio = Number(req.query.anio);
    const mes = Number(req.query.mes);
    if (!Number.isFinite(anio) || !Number.isFinite(mes) || mes < 1 || mes > 12) {
      return null;
    }
    return {
      anio,
      mes,
      categoria: req.query.categoria ? String(req.query.categoria) : undefined,
    };
  }

  agendaGlobal: RequestHandler = async (req, res, next) => {
    try {
      const empresaNit = String(req.params.empresaNit);
      const params = this.paramsFecha(req);
      if (!params) {
        res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
        return;
      }

      const r = await service.agendaGlobalPorHerramienta({
        empresaNit,
        ...params,
      });

      res.json(r);
    } catch (err) {
      next(err);
    }
  };

  agendaConjunto: RequestHandler = async (req, res, next) => {
    try {
      const params = this.paramsFecha(req);
      if (!params) {
        res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
        return;
      }

      const r = await service.agendaGlobalPorHerramienta({
        empresaNit: String(req.user?.empresaId ?? ""),
        conjuntoId: String(req.params.conjuntoId),
        ...params,
      });
      res.json(r);
    } catch (err) {
      next(err);
    }
  };
}
