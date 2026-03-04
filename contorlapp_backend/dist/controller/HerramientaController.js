"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaController = void 0;
const prisma_1 = require("../db/prisma");
const HerramientaServices_1 = require("../services/HerramientaServices");
const Herramienta_1 = require("../model/Herramienta");
class HerramientaController {
    constructor() {
        // POST /herramientas
        this.crear = async (req, res, next) => {
            try {
                const body = Herramienta_1.CrearHerramientaBody.parse(req.body);
                const service = new HerramientaServices_1.HerramientaService(prisma_1.prisma);
                const out = await service.crear(body);
                res.status(201).json(out);
            }
            catch (err) {
                // Unique constraint
                if (err?.code === "P2002") {
                    err.status = 409;
                    err.message =
                        "Ya existe una herramienta con ese nombre/unidad en la empresa.";
                }
                next(err);
            }
        };
        // GET /herramientas?empresaId=&nombre=&take=&skip=
        this.listar = async (req, res, next) => {
            try {
                const q = Herramienta_1.ListarHerramientasQuery.parse(req.query);
                const service = new HerramientaServices_1.HerramientaService(prisma_1.prisma);
                const out = await service.listar(q);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /herramientas/:herramientaId
        this.obtener = async (req, res, next) => {
            try {
                const { herramientaId } = Herramienta_1.HerramientaIdParam.parse(req.params);
                const service = new HerramientaServices_1.HerramientaService(prisma_1.prisma);
                const out = await service.obtenerPorId(herramientaId);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // PATCH /herramientas/:herramientaId
        this.editar = async (req, res, next) => {
            try {
                const { herramientaId } = Herramienta_1.HerramientaIdParam.parse(req.params);
                const body = Herramienta_1.EditarHerramientaBody.parse(req.body);
                const service = new HerramientaServices_1.HerramientaService(prisma_1.prisma);
                const out = await service.editar(herramientaId, body);
                res.json(out);
            }
            catch (err) {
                if (err?.code === "P2002") {
                    err.status = 409;
                    err.message =
                        "Conflicto: ya existe una herramienta con ese nombre/unidad en la empresa.";
                }
                next(err);
            }
        };
        // DELETE /herramientas/:herramientaId
        this.eliminar = async (req, res, next) => {
            try {
                const { herramientaId } = Herramienta_1.HerramientaIdParam.parse(req.params);
                const service = new HerramientaServices_1.HerramientaService(prisma_1.prisma);
                await service.eliminar(herramientaId);
                res.status(204).send();
            }
            catch (err) {
                if (err?.code === "P2003") {
                    err.status = 409;
                    err.message =
                        "No se puede eliminar: está relacionada con stock/solicitudes/usos.";
                }
                next(err);
            }
        };
    }
}
exports.HerramientaController = HerramientaController;
