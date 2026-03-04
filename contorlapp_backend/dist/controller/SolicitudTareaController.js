"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudTareaController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const SolicitudTareaServices_1 = require("../services/SolicitudTareaServices");
const SolicitudIdParam = zod_1.z.object({ solicitudId: zod_1.z.coerce.number().int().positive() });
const RechazarBody = zod_1.z.object({ observacion: zod_1.z.string().min(1).max(500) });
class SolicitudTareaController {
    constructor() {
        // POST /solicitudes-tarea/:solicitudId/aprobar
        this.aprobar = async (req, res, next) => {
            try {
                const { solicitudId } = SolicitudIdParam.parse(req.params);
                const service = new SolicitudTareaServices_1.SolicitudTareaService(prisma_1.prisma, solicitudId);
                await service.aprobar();
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /solicitudes-tarea/:solicitudId/rechazar
        this.rechazar = async (req, res, next) => {
            try {
                const { solicitudId } = SolicitudIdParam.parse(req.params);
                const body = RechazarBody.parse(req.body);
                const service = new SolicitudTareaServices_1.SolicitudTareaService(prisma_1.prisma, solicitudId);
                await service.rechazar(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /solicitudes-tarea/:solicitudId/estado
        this.estadoActual = async (req, res, next) => {
            try {
                const { solicitudId } = SolicitudIdParam.parse(req.params);
                const service = new SolicitudTareaServices_1.SolicitudTareaService(prisma_1.prisma, solicitudId);
                const estado = await service.estadoActual();
                res.json({ estado });
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.SolicitudTareaController = SolicitudTareaController;
