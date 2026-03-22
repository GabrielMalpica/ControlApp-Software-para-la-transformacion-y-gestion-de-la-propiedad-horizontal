"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudHerramientaController = void 0;
const prisma_1 = require("../db/prisma");
const zod_1 = require("zod");
const SolicitudHerramientaService_1 = require("../services/SolicitudHerramientaService");
const Herramienta_1 = require("../model/Herramienta");
const SolicitudIdParam = zod_1.z.object({
    solicitudId: zod_1.z.coerce.number().int().positive(),
});
class SolicitudHerramientaController {
    constructor() {
        // POST /solicitudes-herramientas
        this.crear = async (req, res, next) => {
            try {
                const body = Herramienta_1.CrearSolicitudHerramientaBody.parse(req.body);
                const service = new SolicitudHerramientaService_1.SolicitudHerramientaService(prisma_1.prisma);
                const out = await service.crear(body);
                res.status(201).json(out);
            }
            catch (err) {
                if (err?.code === "P2003") {
                    err.status = 409;
                    err.message = "Conjunto/Empresa/Herramienta no existe.";
                }
                next(err);
            }
        };
        // GET /solicitudes-herramientas?conjuntoId=&empresaId=&estado=
        this.listar = async (req, res, next) => {
            try {
                const conjuntoId = req.query.conjuntoId
                    ? String(req.query.conjuntoId)
                    : undefined;
                const empresaId = req.query.empresaId
                    ? String(req.query.empresaId)
                    : undefined;
                const estado = req.query.estado
                    ? String(req.query.estado)
                    : undefined;
                const service = new SolicitudHerramientaService_1.SolicitudHerramientaService(prisma_1.prisma);
                const out = await service.listar({ conjuntoId, empresaId, estado });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /solicitudes-herramientas/:solicitudId
        this.obtener = async (req, res, next) => {
            try {
                const { solicitudId } = SolicitudIdParam.parse(req.params);
                const service = new SolicitudHerramientaService_1.SolicitudHerramientaService(prisma_1.prisma);
                const out = await service.obtener(solicitudId);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // PATCH /solicitudes-herramientas/:solicitudId/estado
        this.cambiarEstado = async (req, res, next) => {
            try {
                const { solicitudId } = SolicitudIdParam.parse(req.params);
                const body = Herramienta_1.CambiarEstadoSolicitudBody.parse(req.body);
                const service = new SolicitudHerramientaService_1.SolicitudHerramientaService(prisma_1.prisma);
                const out = body.estado === "APROBADA"
                    ? await service.aprobar(solicitudId, req.body)
                    : await service.rechazar(solicitudId, {
                        observacionRespuesta: body.observacionRespuesta ?? null,
                    });
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.SolicitudHerramientaController = SolicitudHerramientaController;
