"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MaquinariaController = exports.ConjuntoIdParam = void 0;
const zod_1 = require("zod");
const client_1 = require("@prisma/client");
const MaquinariaServices_1 = require("../services/MaquinariaServices");
// Params y body mínimos
const MaquinariaIdParam = zod_1.z.object({
    maquinariaId: zod_1.z.coerce.number().int().positive(),
});
exports.ConjuntoIdParam = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
});
const AsignarBody = zod_1.z.object({
    conjuntoId: zod_1.z.string().min(3),
    responsableId: zod_1.z.number().int().positive().optional(),
    diasPrestamo: zod_1.z.number().int().positive().optional(),
});
const AgendaMaquinariaQuery = zod_1.z.object({
    desde: zod_1.z.coerce.date(),
    hasta: zod_1.z.coerce.date(),
});
class MaquinariaController {
    constructor(prisma) {
        // POST /maquinarias/:maquinariaId/asignar
        this.asignarAConjunto = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const body = AsignarBody.parse(req.body);
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const updated = await service.asignarAConjunto(body);
                res.status(201).json(updated);
            }
            catch (err) {
                next(err);
            }
        };
        this.agendaMaquinaria = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const { conjuntoId } = exports.ConjuntoIdParam.parse(req.params);
                const { desde, hasta } = AgendaMaquinariaQuery.parse(req.query);
                if (desde >= hasta) {
                    res.status(400).json({
                        ok: false,
                        reason: "RANGO_INVALIDO",
                        message: "El parámetro 'desde' debe ser menor que 'hasta'.",
                    });
                    return;
                }
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const agenda = await service.agendaMaquinariaPorMaquina({
                    maquinariaId,
                    conjuntoId,
                    desde,
                    hasta,
                });
                res.status(200).json({
                    ok: true,
                    data: agenda,
                });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /maquinarias/:maquinariaId/devolver
        this.devolver = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const { conjuntoId } = exports.ConjuntoIdParam.parse(req.params); // crea este param
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const updated = await service.devolver(conjuntoId);
                res.status(200).json(updated);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /maquinarias/:maquinariaId/disponible
        this.estaDisponible = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const disponible = await service.estaDisponible();
                res.json({ disponible });
            }
            catch (err) {
                next(err);
            }
        };
        // GET /maquinarias/:maquinariaId/responsable
        this.obtenerResponsable = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const { conjuntoId } = exports.ConjuntoIdParam.parse(req.params);
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const responsable = await service.obtenerResponsableEnConjunto(conjuntoId);
                res.json({ responsable });
            }
            catch (err) {
                next(err);
            }
        };
        // GET /maquinarias/:maquinariaId/resumen
        this.resumenEstado = async (req, res, next) => {
            try {
                const { maquinariaId } = MaquinariaIdParam.parse(req.params);
                const service = new MaquinariaServices_1.MaquinariaService(this.prisma, maquinariaId);
                const resumen = await service.resumenEstado();
                res.json({ resumen });
            }
            catch (err) {
                next(err);
            }
        };
        this.prisma = prisma ?? new client_1.PrismaClient();
    }
}
exports.MaquinariaController = MaquinariaController;
