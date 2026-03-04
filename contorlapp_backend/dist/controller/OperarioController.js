"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.OperarioController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const OperarioServices_1 = require("../services/OperarioServices");
const InventarioServices_1 = require("../services/InventarioServices");
// ── Schemas ─────────────────────────────────────────────────────────────────
const OperarioIdParam = zod_1.z.object({ operarioId: zod_1.z.coerce.number().int().positive() });
const TareaIdParam = zod_1.z.object({ tareaId: zod_1.z.coerce.number().int().positive() });
// Query/body helpers
const FechaQuery = zod_1.z.object({ fecha: zod_1.z.coerce.date() });
const AsignarBody = zod_1.z.object({
    tareaId: zod_1.z.number().int().positive(),
});
const CompletarBody = zod_1.z.object({
    tareaId: zod_1.z.number().int().positive(),
    evidencias: zod_1.z.array(zod_1.z.string()).optional().default([]),
    insumosUsados: zod_1.z
        .array(zod_1.z.object({
        insumoId: zod_1.z.number().int().positive(),
        cantidad: zod_1.z.number().int().positive(),
    }))
        .optional()
        .default([]),
});
class OperarioController {
    constructor() {
        // POST /operarios/:operarioId/tareas/asignar
        this.asignarTarea = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { tareaId } = AsignarBody.parse(req.body);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                await service.asignarTarea({ tareaId });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /operarios/:operarioId/tareas/:tareaId/iniciar
        this.iniciarTarea = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { tareaId } = TareaIdParam.parse(req.params);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                await service.iniciarTarea({ tareaId });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /operarios/:operarioId/tareas/completar
        this.marcarComoCompletada = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const body = CompletarBody.parse(req.body);
                // 1) Resolver inventario del conjunto de la tarea
                const tarea = await prisma_1.prisma.tarea.findUnique({
                    where: { id: body.tareaId },
                    select: { conjuntoId: true },
                });
                if (!tarea?.conjuntoId) {
                    const e = new Error("La tarea no existe o no tiene conjunto asignado.");
                    e.status = 400;
                    throw e;
                }
                const inventario = await prisma_1.prisma.inventario.findUnique({
                    where: { conjuntoId: tarea.conjuntoId },
                    select: { id: true },
                });
                if (!inventario) {
                    const e = new Error("No existe inventario para el conjunto de la tarea.");
                    e.status = 400;
                    throw e;
                }
                // 2) Ejecutar flujo de cierre con consumo de insumos
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const inventarioService = new InventarioServices_1.InventarioService(prisma_1.prisma, inventario.id);
                await service.marcarComoCompletada(body, inventarioService);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // POST /operarios/:operarioId/tareas/:tareaId/cerrar
        this.cerrarTareaConEvidencias = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { tareaId } = TareaIdParam.parse(req.params);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const files = req.files ?? [];
                await service.cerrarTareaConEvidencias(tareaId, {
                    observaciones: req.body.observaciones,
                    fechaFinalizarTarea: req.body.fechaFinalizarTarea,
                    insumosUsados: req.body.insumosUsados,
                }, files);
                res.json({ ok: true });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /operarios/:operarioId/tareas/:tareaId/no-completada
        this.marcarComoNoCompletada = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { tareaId } = TareaIdParam.parse(req.params);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                await service.marcarComoNoCompletada({ tareaId });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /operarios/:operarioId/tareas/dia?fecha=YYYY-MM-DD
        this.tareasDelDia = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { fecha } = FechaQuery.parse(req.query);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const tareas = await service.tareasDelDia({ fecha });
                res.json(tareas);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /operarios/:operarioId/tareas
        this.listarTareas = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const list = await service.listarTareas();
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /operarios/:operarioId/horas/restantes?fecha=YYYY-MM-DD
        this.horasRestantesEnSemana = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { fecha } = FechaQuery.parse(req.query);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const horas = await service.horasRestantesEnSemana({ fecha });
                res.json({ horasRestantes: horas });
            }
            catch (err) {
                next(err);
            }
        };
        // GET /operarios/:operarioId/horas/resumen?fecha=YYYY-MM-DD
        this.resumenDeHoras = async (req, res, next) => {
            try {
                const { operarioId } = OperarioIdParam.parse(req.params);
                const { fecha } = FechaQuery.parse(req.query);
                const service = new OperarioServices_1.OperarioService(prisma_1.prisma, operarioId);
                const resumen = await service.resumenDeHoras({ fecha });
                res.json({ resumen });
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.OperarioController = OperarioController;
