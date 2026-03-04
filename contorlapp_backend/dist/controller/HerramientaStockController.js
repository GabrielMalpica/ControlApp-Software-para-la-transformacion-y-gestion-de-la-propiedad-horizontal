"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaStockController = void 0;
const prisma_1 = require("../db/prisma");
const Herramienta_1 = require("../model/Herramienta");
const HerramientaStockService_1 = require("../services/HerramientaStockService");
const zod_1 = require("zod");
const HerramientaIdParam = zod_1.z.object({
    herramientaId: zod_1.z.coerce.number().int().positive(),
});
class HerramientaStockController {
    constructor() {
        // GET /herramientas/conjunto/:nit/stock?estado=
        this.listarStockConjunto = async (req, res, next) => {
            try {
                const { nit } = Herramienta_1.ConjuntoNitParam.parse(req.params);
                const estado = req.query.estado ? String(req.query.estado) : undefined;
                const service = new HerramientaStockService_1.HerramientaStockService(prisma_1.prisma, nit);
                const out = await service.listarStock({ estado: estado });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /herramientas/conjunto/:nit/stock  (upsert)
        this.upsertStockConjunto = async (req, res, next) => {
            try {
                const { nit } = Herramienta_1.ConjuntoNitParam.parse(req.params);
                const body = Herramienta_1.UpsertStockBody.parse(req.body);
                const service = new HerramientaStockService_1.HerramientaStockService(prisma_1.prisma, nit);
                const out = await service.upsertStock({
                    herramientaId: body.herramientaId,
                    cantidad: Number(body.cantidad),
                    estado: body.estado,
                });
                res.status(201).json(out);
            }
            catch (err) {
                if (err?.code === "P2003") {
                    err.status = 409;
                    err.message = "Conjunto o herramienta no existe.";
                }
                next(err);
            }
        };
        // PATCH /herramientas/conjunto/:nit/stock/:herramientaId/ajustar
        this.ajustarStockConjunto = async (req, res, next) => {
            try {
                const { nit } = Herramienta_1.ConjuntoNitParam.parse(req.params);
                const { herramientaId } = HerramientaIdParam.parse(req.params);
                const body = Herramienta_1.AjustarStockBody.parse(req.body);
                const service = new HerramientaStockService_1.HerramientaStockService(prisma_1.prisma, nit);
                const out = await service.ajustarStock({
                    herramientaId,
                    delta: Number(body.delta),
                    estado: body.estado,
                });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // DELETE /herramientas/conjunto/:nit/stock/:herramientaId?estado=
        this.eliminarStockConjunto = async (req, res, next) => {
            try {
                const { nit } = Herramienta_1.ConjuntoNitParam.parse(req.params);
                const { herramientaId } = HerramientaIdParam.parse(req.params);
                const estado = (req.query.estado ? String(req.query.estado) : "OPERATIVA");
                const service = new HerramientaStockService_1.HerramientaStockService(prisma_1.prisma, nit);
                await service.eliminarStock({ herramientaId, estado });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.HerramientaStockController = HerramientaStockController;
