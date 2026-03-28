"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CompromisoConjuntoController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const CompromisoConjuntoService_1 = require("../services/CompromisoConjuntoService");
const service = new CompromisoConjuntoService_1.CompromisoConjuntoService(prisma_1.prisma);
const ConjuntoParam = zod_1.z.object({ conjuntoId: zod_1.z.string().min(1) });
const CompromisoParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const CrearBody = zod_1.z.object({ titulo: zod_1.z.string().min(1) });
const ActualizarBody = zod_1.z.object({
    titulo: zod_1.z.string().min(1).optional(),
    completado: zod_1.z.boolean().optional(),
});
class CompromisoConjuntoController {
    constructor() {
        this.listarGlobal = async (_req, res, next) => {
            try {
                const items = await service.listarGlobal();
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarPorConjunto = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoParam.parse(req.params);
                const items = await service.listarPorConjunto(conjuntoId);
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.crear = async (req, res, next) => {
            try {
                const { conjuntoId } = ConjuntoParam.parse(req.params);
                const { titulo } = CrearBody.parse(req.body);
                const creado = await service.crear({
                    conjuntoId,
                    titulo,
                    creadoPorId: req.user?.sub ? String(req.user.sub) : null,
                });
                res.status(201).json(creado);
            }
            catch (err) {
                next(err);
            }
        };
        this.actualizar = async (req, res, next) => {
            try {
                const { id } = CompromisoParam.parse(req.params);
                const body = ActualizarBody.parse(req.body);
                const updated = await service.actualizar(id, body);
                res.json(updated);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminar = async (req, res, next) => {
            try {
                const { id } = CompromisoParam.parse(req.params);
                const out = await service.eliminar(id);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.CompromisoConjuntoController = CompromisoConjuntoController;
