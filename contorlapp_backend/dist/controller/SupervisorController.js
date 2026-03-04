"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SupervisorController = void 0;
const prisma_1 = require("../db/prisma");
const zod_1 = require("zod");
const SupervisorServices_1 = require("../services/SupervisorServices");
// Params
const IdParamSchema = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
// Query filtros (ajústalo si tu service espera otros nombres)
const ListarSchema = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
    operarioId: zod_1.z.coerce.string().optional(), // si viene string, tu service decide si lo parsea
    estado: zod_1.z.string().optional(),
    desde: zod_1.z.string().optional(),
    hasta: zod_1.z.string().optional(),
    borrador: zod_1.z
        .union([zod_1.z.literal("true"), zod_1.z.literal("false")])
        .optional()
        .transform((v) => (v == null ? undefined : v === "true")),
});
function getSupervisorIdFromReq(req) {
    // ✅ TU AUTH GUARDA EL ID EN sub
    const sid = req.user?.sub;
    if (!sid)
        throw new Error("No se pudo identificar supervisorId en el token.");
    return String(sid);
}
class SupervisorController {
    constructor() {
        // GET /supervisor/tareas
        this.listarTareas = async (req, res, next) => {
            try {
                const supervisorId = getSupervisorIdFromReq(req);
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, supervisorId);
                const q = ListarSchema.parse(req.query);
                const payload = {
                    conjuntoId: q.conjuntoId,
                    operarioId: q.operarioId, // si quieres, conviértelo aquí
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
                const supervisorId = String(req.user?.id ?? req.headers["x-user-id"] ?? "");
                // ajusta a tu auth real
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
        // POST /supervisor/tareas/:id/cerrar
        this.cerrarTarea = async (req, res, next) => {
            try {
                const supervisorId = getSupervisorIdFromReq(req);
                const svc = new SupervisorServices_1.SupervisorService(prisma_1.prisma, supervisorId);
                const tareaId = Number(req.params.id);
                if (!Number.isFinite(tareaId) || tareaId <= 0) {
                    res.status(400).json({ error: "id inválido" });
                    return;
                }
                const files = req.files ?? [];
                await svc.cerrarTareaConEvidencias(tareaId, {
                    // body viene como strings en multipart
                    observaciones: req.body.observaciones,
                    fechaFinalizarTarea: req.body.fechaFinalizarTarea,
                    insumosUsados: req.body.insumosUsados,
                }, files);
                res.json({ ok: true });
            }
            catch (e) {
                next(e);
            }
        };
        // POST /supervisor/tareas/:id/veredicto
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
