"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NotificacionController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const CumpleanosService_1 = require("../services/CumpleanosService");
const NotificacionService_1 = require("../services/NotificacionService");
const ListarQuery = zod_1.z.object({
    limit: zod_1.z.coerce.number().int().min(1).max(100).optional(),
    soloNoLeidas: zod_1.z
        .string()
        .optional()
        .transform((v) => v === "true"),
});
const IdParam = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
const service = new NotificacionService_1.NotificacionService(prisma_1.prisma);
const cumpleanosService = new CumpleanosService_1.CumpleanosService(prisma_1.prisma);
function getUsuarioAutenticado(req) {
    const id = req.user?.sub;
    if (!id)
        return null;
    return String(id);
}
class NotificacionController {
    constructor() {
        this.listar = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                await cumpleanosService.asegurarNotificacionesCumpleanosHoy(usuarioId);
                const q = ListarQuery.parse(req.query ?? {});
                const items = await service.listarUsuario(usuarioId, {
                    limit: q.limit,
                    soloNoLeidas: q.soloNoLeidas,
                });
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.contarNoLeidas = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                await cumpleanosService.asegurarNotificacionesCumpleanosHoy(usuarioId);
                const total = await service.contarNoLeidas(usuarioId);
                res.json({ total });
            }
            catch (err) {
                next(err);
            }
        };
        this.marcarLeida = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const { id } = IdParam.parse(req.params);
                const ok = await service.marcarLeida(usuarioId, id);
                if (!ok) {
                    res.status(404).json({ message: "Notificacion no encontrada" });
                    return;
                }
                const total = await service.contarNoLeidas(usuarioId);
                res.json({ ok: true, totalNoLeidas: total });
            }
            catch (err) {
                next(err);
            }
        };
        this.marcarTodasLeidas = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const actualizadas = await service.marcarTodasLeidas(usuarioId);
                res.json({ ok: true, actualizadas, totalNoLeidas: 0 });
            }
            catch (err) {
                next(err);
            }
        };
        this.cumpleanosMesActual = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const items = await cumpleanosService.listarCumpleanosMesActor(usuarioId);
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.cumpleanosHoy = async (req, res, next) => {
            try {
                const usuarioId = getUsuarioAutenticado(req);
                if (!usuarioId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                await cumpleanosService.asegurarNotificacionesCumpleanosHoy(usuarioId);
                const info = await cumpleanosService.cumpleanosHoyActor(usuarioId);
                res.json(info);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.NotificacionController = NotificacionController;
