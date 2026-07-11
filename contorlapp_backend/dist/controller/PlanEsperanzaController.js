"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlanEsperanzaController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const PlanEsperanzaService_1 = require("../services/PlanEsperanzaService");
const service = new PlanEsperanzaService_1.PlanEsperanzaService(prisma_1.prisma);
const NitParam = zod_1.z.object({ nit: zod_1.z.string().min(1) });
const PlanIdParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const DiagnosticoIdParam = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
class PlanEsperanzaController {
    constructor() {
        this.getConfig = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const config = await service.obtenerConfig(nit);
                res.json(config);
            }
            catch (err) {
                next(err);
            }
        };
        this.updateConfig = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const { intervaloMeses } = zod_1.z
                    .object({ intervaloMeses: zod_1.z.number().int().min(1).max(60) })
                    .parse(req.body);
                const config = await service.actualizarConfig(nit, intervaloMeses);
                res.json(config);
            }
            catch (err) {
                next(err);
            }
        };
        this.iniciarPlan = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const { mantenerEvidencias, planAnteriorId } = zod_1.z
                    .object({
                    mantenerEvidencias: zod_1.z.boolean().optional().default(false),
                    planAnteriorId: zod_1.z.number().int().positive().optional(),
                })
                    .parse(req.body);
                const plan = await service.iniciarPlan(nit, mantenerEvidencias, planAnteriorId);
                res.status(201).json(plan);
            }
            catch (err) {
                next(err);
            }
        };
        this.getPlanActivo = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const plan = await service.obtenerPlanActivo(nit);
                res.json(plan);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarPlanes = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const planes = await service.listarPlanes(nit);
                res.json(planes);
            }
            catch (err) {
                next(err);
            }
        };
        this.guardarDiagnostico = async (req, res, next) => {
            try {
                const { id } = DiagnosticoIdParam.parse(req.params);
                const body = zod_1.z
                    .object({
                    valoracion: zod_1.z.coerce.number().min(0).max(5).optional().nullable(),
                    observaciones: zod_1.z.string().optional().nullable(),
                })
                    .parse(req.body);
                const file = req.file;
                let conjuntoNombre;
                if (file) {
                    const diagnostico = await service.obtenerDiagnostico(id);
                    if (!diagnostico) {
                        res.status(404).json({ error: "Diagnostico no encontrado" });
                        return;
                    }
                    const conjunto = await prisma_1.prisma.conjunto.findUnique({
                        where: { nit: diagnostico.conjuntoId },
                        select: { nombre: true },
                    });
                    conjuntoNombre = conjunto?.nombre ?? "Conjunto";
                    const result = await service.guardarDiagnostico(id, {
                        valoracion: body.valoracion,
                        observaciones: body.observaciones,
                        filePath: file.path,
                        fileName: `area_${diagnostico.elementoId}_${Date.now()}${file.originalname ? file.originalname.substring(file.originalname.lastIndexOf(".")) : ".jpg"}`,
                        mimeType: file.mimetype,
                        conjuntoNombre,
                    });
                    res.json(result);
                }
                else {
                    const result = await service.guardarDiagnostico(id, {
                        valoracion: body.valoracion,
                        observaciones: body.observaciones,
                    });
                    res.json(result);
                }
            }
            catch (err) {
                next(err);
            }
        };
        this.finalizarPlan = async (req, res, next) => {
            try {
                const { id } = PlanIdParam.parse(req.params);
                const plan = await service.finalizarPlan(id);
                res.json(plan);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtenerInforme = async (req, res, next) => {
            try {
                const { id } = PlanIdParam.parse(req.params);
                const informe = await service.obtenerInforme(id);
                if (!informe) {
                    res.status(404).json({ error: "Plan no encontrado" });
                    return;
                }
                res.json(informe);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtenerHistorico = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const { planIds } = zod_1.z
                    .object({ planIds: zod_1.z.string().optional() })
                    .parse(req.query);
                const selectedPlanIds = planIds
                    ?.split(",")
                    .map((id) => Number(id.trim()))
                    .filter((id) => Number.isInteger(id) && id > 0);
                const historico = await service.obtenerHistorico(nit, selectedPlanIds?.length ? selectedPlanIds : undefined);
                res.json(historico);
            }
            catch (err) {
                next(err);
            }
        };
        this.reiniciarPlan = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const { mantenerEvidencias } = zod_1.z
                    .object({
                    mantenerEvidencias: zod_1.z.boolean().optional().default(false),
                })
                    .parse(req.body);
                const plan = await service.reiniciarPlan(nit, mantenerEvidencias);
                res.json(plan);
            }
            catch (err) {
                next(err);
            }
        };
        this.verificarZonasNuevas = async (req, res, next) => {
            try {
                const { nit } = NitParam.parse(req.params);
                const resultado = await service.verificarZonasNuevas(nit);
                res.json(resultado);
            }
            catch (err) {
                next(err);
            }
        };
        this.obtenerLineaTiempoElemento = async (req, res, next) => {
            try {
                const { elementoId } = zod_1.z
                    .object({ elementoId: zod_1.z.coerce.number().int().positive() })
                    .parse(req.params);
                const entries = await service.obtenerLineaTiempoElemento(elementoId);
                res.json(entries);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.PlanEsperanzaController = PlanEsperanzaController;
