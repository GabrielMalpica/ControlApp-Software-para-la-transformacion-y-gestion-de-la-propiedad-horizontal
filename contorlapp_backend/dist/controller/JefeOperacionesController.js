"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.JefeOperacionesController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const JefeOperacionesService_1 = require("../services/JefeOperacionesService");
const IdParamSchema = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
const ListarPendientesQuerySchema = zod_1.z.object({
    conjuntoId: zod_1.z.string().optional(),
});
const VeredictoBodySchema = zod_1.z.object({
    accion: zod_1.z.enum(["APROBAR", "RECHAZAR", "NO_COMPLETADA"]),
    observacionesRechazo: zod_1.z.string().min(3).max(500).optional(),
    fechaVerificacion: zod_1.z.coerce.date().optional(),
});
/**
 * ✅ Lee empresaId desde:
 * - req.user.empresaId (si ya existe)
 * - header x-empresa-id (para Flutter)
 *
 * Devuelve number o null (si no se puede)
 */
function getEmpresaIdFromReq(req) {
    const raw = req.user?.empresaId ?? req.headers["x-empresa-id"];
    const n = Number(raw);
    if (!Number.isFinite(n) || n <= 0)
        return null;
    return n;
}
class JefeOperacionesController {
    constructor() {
        // GET /jefe-operaciones/tareas/pendientes?conjuntoId=...
        this.listarPendientes = async (req, res, next) => {
            try {
                const query = ListarPendientesQuerySchema.parse(req.query ?? {});
                const empresaId = getEmpresaIdFromReq(req);
                const svc = new JefeOperacionesService_1.JefeOperacionesService(prisma_1.prisma, empresaId);
                const rows = await svc.listarPendientes(query.conjuntoId);
                // Flutter espera List
                res.json(rows);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /jefe-operaciones/tareas/:id/veredicto (JSON)
        this.veredicto = async (req, res, next) => {
            try {
                const { id: tareaId } = IdParamSchema.parse(req.params);
                const body = VeredictoBodySchema.parse(req.body ?? {});
                const empresaId = getEmpresaIdFromReq(req);
                const inicio = Date.now();
                const svc = new JefeOperacionesService_1.JefeOperacionesService(prisma_1.prisma, empresaId);
                const out = await svc.veredicto(tareaId, body);
                console.log(`[perf] Veredicto jefe operaciones tarea #${tareaId} (${body.accion}): ${((Date.now() - inicio) /
                    1000).toFixed(2)} s`);
                res.json(out ?? { ok: true });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /jefe-operaciones/tareas/:id/veredicto-multipart
        this.veredictoMultipart = async (req, res, next) => {
            try {
                const { id: tareaId } = IdParamSchema.parse(req.params);
                const files = (req.files ?? []);
                const empresaId = getEmpresaIdFromReq(req);
                const inicio = Date.now();
                const svc = new JefeOperacionesService_1.JefeOperacionesService(prisma_1.prisma, empresaId);
                const out = await svc.veredictoConEvidencias(tareaId, req.body, files);
                const accion = typeof req.body?.accion === 'string' ? req.body.accion : 'SIN_ACCION';
                console.log(`[perf] Veredicto jefe operaciones tarea #${tareaId} (${accion}, ${files.length} evidencia(s)): ${((Date.now() - inicio) /
                    1000).toFixed(2)} s`);
                res.json(out ?? { ok: true });
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.JefeOperacionesController = JefeOperacionesController;
