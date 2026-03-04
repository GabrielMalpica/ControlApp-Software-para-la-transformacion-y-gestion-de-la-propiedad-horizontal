"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudInsumoController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const SolicitudInsumoServices_1 = require("../services/SolicitudInsumoServices");
const IdParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const FiltroQuery = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    empresaId: zod_1.z.string().optional(),
    aprobado: zod_1.z.coerce.boolean().optional(),
    fechaDesde: zod_1.z.coerce.date().optional(),
    fechaHasta: zod_1.z.coerce.date().optional(),
});
// aprobar puede venir vacío
const AprobarBody = zod_1.z.object({
    fechaAprobacion: zod_1.z.coerce.date().optional(),
    empresaId: zod_1.z.string().min(3).optional(),
});
const service = new SolicitudInsumoServices_1.SolicitudInsumoService(prisma_1.prisma);
class SolicitudInsumoController {
    constructor() {
        this.crear = async (req, res, next) => {
            try {
                const actorId = req.user?.sub ? String(req.user.sub) : null;
                const out = await service.crear(req.body, actorId);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.aprobar = async (req, res, next) => {
            try {
                const { id } = IdParam.parse(req.params);
                const body = AprobarBody.parse(req.body ?? {});
                const out = await service.aprobar(id, body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.listar = async (req, res, next) => {
            try {
                const f = FiltroQuery.parse(req.query);
                const out = await service.listar(f);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtener = async (req, res, next) => {
            try {
                const { id } = IdParam.parse(req.params);
                const out = await service.obtener(id);
                if (!out) {
                    res.status(404).json({ message: "No encontrado" });
                    return;
                }
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminar = async (req, res, next) => {
            try {
                const { id } = IdParam.parse(req.params);
                await service.eliminar(id);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.SolicitudInsumoController = SolicitudInsumoController;
