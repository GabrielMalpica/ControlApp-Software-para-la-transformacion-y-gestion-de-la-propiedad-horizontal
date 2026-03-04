"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgendaMaquinariaController = void 0;
const prisma_1 = require("../db/prisma");
const AgendaMaquinariaService_1 = require("../services/AgendaMaquinariaService");
const service = new AgendaMaquinariaService_1.AgendaMaquinariaService(prisma_1.prisma);
class AgendaMaquinariaController {
    constructor() {
        this.agendaGlobal = async (req, res, next) => {
            try {
                const empresaNit = String(req.params.empresaNit);
                const anio = Number(req.query.anio);
                const mes = Number(req.query.mes);
                const tipo = req.query.tipo ? String(req.query.tipo) : undefined;
                if (!Number.isFinite(anio) ||
                    !Number.isFinite(mes) ||
                    mes < 1 ||
                    mes > 12) {
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
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.AgendaMaquinariaController = AgendaMaquinariaController;
