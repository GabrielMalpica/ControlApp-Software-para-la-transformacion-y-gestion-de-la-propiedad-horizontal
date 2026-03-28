import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { AgendaHerramientaService } from "../services/AgendaHerramientaService";

const service = new AgendaHerramientaService(prisma);

export class AgendaHerramientaController {
  agendaGlobal: RequestHandler = async (req, res, next) => {
    try {
      const empresaNit = String(req.params.empresaNit);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const categoria = req.query.categoria
        ? String(req.query.categoria)
        : undefined;

      if (!Number.isFinite(anio) || !Number.isFinite(mes) || mes < 1 || mes > 12) {
        res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
        return;
      }

      const r = await service.agendaGlobalPorHerramienta({
        empresaNit,
        anio,
        mes,
        categoria,
      });

      res.json(r);
    } catch (err) {
      next(err);
    }
  };
}
