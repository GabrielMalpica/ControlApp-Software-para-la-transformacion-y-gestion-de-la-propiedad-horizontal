"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupervisorController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const SupervisorServices_1 = require("../services/SupervisorServices");
const IdParamSchema = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
const ListarSchema = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    operarioId: zod_1.z.coerce.string().optional(),
    estado: zod_1.z.string().optional(),
    desde: zod_1.z.string().optional(),
    hasta: zod_1.z.string().optional(),
    borrador: zod_1.z
        .union([zod_1.z.literal("true"), zod_1.z.literal("false")])
        .optional()
        .transform((v) => (v == null ? undefined : v === "true")),
});
function forbiddenError(message = "No autorizado para este recurso") {
    const err = new Error(message);
    err.status = 403;
    return err;
}
function getActorFromReq(req) {
    const id = req.user?.sub;
    const rol = String(req.user?.rol ?? "").trim().toLowerCase();
    if (!id) {
        throw new Error("No se pudo identificar el usuario autenticado.");
    }
    switch (rol) {
        case "supervisor":
            return { id: String(id), rol: "SUPERVISOR" };
        case "gerente":
            return { id: String(id), rol: "GERENTE" };
        case "jefe_operaciones":
            return { id: String(id), rol: "JEFE_OPERACIONES" };
        default:
            throw forbiddenError();
    }
}
function getSupervisorIdFromReq(req) {
    const actor = getActorFromReq(req);
    if (actor.rol !== "SUPERVISOR") {
        throw forbiddenError();
    }
    return actor.id;
}
class SupervisorController {
    constructor() {
        this.listarTareas = async (req, res, next) => {
            try {
                const supervisorId = getSupervisorIdFromReq(req);
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, supervisorId);
                const q = ListarSchema.parse(req.query);
                const payload = {
                    conjuntoId: q.conjuntoId,
                    operarioId: q.operarioId,
                    estado: q.estado,
                    desde: q.desde,
                    hasta: q.hasta,
                    borrador: q.borrador,
                };
                const data = await svc.listarTareas(payload);
                res.json(data);
            }
            catch (err) {
                next(err);
            }
        };
        this.cronogramaImprimible = async (req, res, next) => {
            try {
                const supervisorId = getSupervisorIdFromReq(req);
                const conjuntoId = String(req.query.conjuntoId ?? "");
                const operarioId = String(req.query.operarioId ?? "");
                const desde = req.query.desde
                    ? new Date(String(req.query.desde))
                    : undefined;
                const hasta = req.query.hasta
                    ? new Date(String(req.query.hasta))
                    : undefined;
                if (!conjuntoId || !operarioId || !desde || !hasta) {
                    res.status(400).json({ ok: false, reason: "PARAMS_INVALIDOS" });
                    return;
                }
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, supervisorId);
                const r = await svc.cronogramaImprimible({
                    conjuntoId,
                    operarioId,
                    desde,
                    hasta,
                });
                res.json(r);
            }
            catch (err) {
                next(err);
            }
        };
        this.cerrarTarea = async (req, res, next) => {
            try {
                const actor = getActorFromReq(req);
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, actor.id, actor.rol);
                const inicio = Date.now();
                const tareaId = Number(req.params.id);
                if (!Number.isFinite(tareaId) || tareaId <= 0) {
                    res.status(400).json({ error: "id invalido" });
                    return;
                }
                if (actor.rol === "SUPERVISOR") {
                    const tarea = await prisma_1.prisma.tarea.findUnique({
                        where: { id: tareaId },
                        select: {
                            supervisorId: true,
                            descripcion: true,
                            conjunto: { select: { nombre: true } },
                        },
                    });
                    if (!tarea?.supervisorId || tarea.supervisorId !== actor.id) {
                        throw forbiddenError("No tiene autorizacion para cerrar esta tarea.");
                    }
                    const files = req.files ?? [];
                    await svc.cerrarTareaConEvidencias(tareaId, {
                        observaciones: req.body.observaciones,
                        fechaFinalizarTarea: req.body.fechaFinalizarTarea,
                        insumosUsados: req.body.insumosUsados,
                    }, files);
                    const conjunto = (tarea.conjunto?.nombre ?? '').trim();
                    const detalle = conjunto.length > 0
                        ? `${conjunto} - tarea #${tareaId}`
                        : `tarea #${tareaId}`;
                    console.log(`[perf] Cierre tarea supervisor ${detalle} (${files.length} evidencia(s)): ${((Date.now() - inicio) /
                        1000).toFixed(2)} s`);
                    res.json({ ok: true });
                    return;
                }
                const files = req.files ?? [];
                await svc.cerrarTareaConEvidencias(tareaId, {
                    observaciones: req.body.observaciones,
                    fechaFinalizarTarea: req.body.fechaFinalizarTarea,
                    insumosUsados: req.body.insumosUsados,
                }, files);
                const tarea = await prisma_1.prisma.tarea.findUnique({
                    where: { id: tareaId },
                    select: { conjunto: { select: { nombre: true } } },
                });
                const conjunto = (tarea?.conjunto?.nombre ?? '').trim();
                const detalle = conjunto.length > 0
                    ? `${conjunto} - tarea #${tareaId}`
                    : `tarea #${tareaId}`;
                console.log(`[perf] Cierre tarea ${actor.rol.toLowerCase()} ${detalle} (${files.length} evidencia(s)): ${((Date.now() - inicio) /
                    1000).toFixed(2)} s`);
                res.json({ ok: true });
            }
            catch (e) {
                next(e);
            }
        };
        this.veredicto = async (req, res, next) => {
            try {
                const supervisorId = getSupervisorIdFromReq(req);
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, supervisorId);
                const { id } = IdParamSchema.parse(req.params);
                await svc.veredicto(id, req.body);
                res.json({ ok: true });
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.SupervisorController = SupervisorController;
