// src/controller/AgendaMaquinariaController.ts
import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { AgendaMaquinariaService } from "../services/AgendaMaquinariaService";

const service = new AgendaMaquinariaService(prisma);

export class AgendaMaquinariaController {
  agendaGlobal: RequestHandler = async (req, res, next) => {
    try {
      const empresaNit = String(req.params.empresaNit);
      const anio = Number(req.query.anio);
      const mes = Number(req.query.mes);
      const tipo = req.query.tipo ? String(req.query.tipo) : undefined;

      if (
        !Number.isFinite(anio) ||
        !Number.isFinite(mes) ||
        mes < 1 ||
        mes > 12
      ) {
        res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
        return;
      }

      const r = await service.agendaGlobalPorMaquina({
        empresaNit,
        anio,
        mes,
        tipo,
      });

      res.json(r);
    } catch (err) {
      next(err);
    }
  };
}
