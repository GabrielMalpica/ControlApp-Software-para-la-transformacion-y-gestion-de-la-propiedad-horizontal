"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudMaquinariaController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const SolicitudMaquinariaServices_1 = require("../services/SolicitudMaquinariaServices");
const IdParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const FiltroQuery = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    empresaId: zod_1.z.string().optional(),
    maquinariaId: zod_1.z.coerce.number().int().optional(),
    operarioId: zod_1.z.coerce.number().int().optional(),
    aprobado: zod_1.z.coerce.boolean().optional(),
    fechaDesde: zod_1.z.coerce.date().optional(),
    fechaHasta: zod_1.z.coerce.date().optional(),
});
const service = new SolicitudMaquinariaServices_1.SolicitudMaquinariaService(prisma_1.prisma);
class SolicitudMaquinariaController {
    constructor() {
        this.crear = async (req, res, next) => {
            try {
                const out = await service.crear(req.body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.editar = async (req, res, next) => {
            try {
                const { id } = IdParam.parse(req.params);
                const out = await service.editar(id, req.body);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        this.aprobar = async (req, res, next) => {
            try {
                const { id } = IdParam.parse(req.params);
                const out = await service.aprobar(id, req.body);
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
exports.SolicitudMaquinariaController = SolicitudMaquinariaController;
