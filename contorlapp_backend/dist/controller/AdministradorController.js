"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AdministradorController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const AdministradorServices_1 = require("../services/AdministradorServices");
// Validaciones mínimas para params / headers / query
const AdminIdParam = zod_1.z.object({ adminId: zod_1.z.coerce.number().int().positive() });
const ConjuntoParam = zod_1.z.object({ conjuntoId: zod_1.z.string().min(1) });
const CompromisoParam = zod_1.z.object({ id: zod_1.z.coerce.number().int().positive() });
const CrearCompromisoBody = zod_1.z.object({ titulo: zod_1.z.string().min(1) });
const ActualizarCompromisoBody = zod_1.z.object({
    titulo: zod_1.z.string().min(1).optional(),
    completado: zod_1.z.boolean().optional(),
});
// Puedes aceptar adminId también por header o query si te conviene multi-uso
function resolveAdminId(req) {
    const paramId = req.params?.adminId;
    const headerId = req.header("x-admin-id");
    const queryId = typeof req.query.adminId === "string" ? req.query.adminId : undefined;
    const parsed = AdminIdParam.safeParse({ adminId: paramId ?? headerId ?? queryId });
    if (!parsed.success) {
        const e = new Error("Falta o es inválido el administradorId.");
        e.status = 400;
        throw e;
    }
    return parsed.data.adminId;
}
class AdministradorController {
    constructor() {
        // GET /administradores/:adminId/conjuntos
        this.verConjuntos = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const conjuntos = await service.verConjuntos();
                res.json(conjuntos);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /administradores/:adminId/solicitudes/tarea
        this.solicitarTarea = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const creada = await service.solicitarTarea(req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /administradores/:adminId/solicitudes/insumos
        this.solicitarInsumos = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const creada = await service.solicitarInsumos(req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /administradores/:adminId/solicitudes/maquinaria
        this.solicitarMaquinaria = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const creada = await service.solicitarMaquinaria(req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        this.listarCompromisosConjunto = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const { conjuntoId } = ConjuntoParam.parse(req.params);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const items = await service.listarCompromisosConjunto(conjuntoId);
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        this.crearCompromisoConjunto = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const { conjuntoId } = ConjuntoParam.parse(req.params);
                const { titulo } = CrearCompromisoBody.parse(req.body);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const creado = await service.crearCompromisoConjunto({
                    conjuntoId,
                    titulo,
                    creadoPorId: req.user?.sub ? String(req.user.sub) : administradorId.toString(),
                });
                res.status(201).json(creado);
            }
            catch (err) {
                next(err);
            }
        };
        this.actualizarCompromiso = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const { id } = CompromisoParam.parse(req.params);
                const body = ActualizarCompromisoBody.parse(req.body);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const updated = await service.actualizarCompromiso(id, body);
                res.json(updated);
            }
            catch (err) {
                next(err);
            }
        };
        this.eliminarCompromiso = async (req, res, next) => {
            try {
                const administradorId = resolveAdminId(req);
                const { id } = CompromisoParam.parse(req.params);
                const service = new AdministradorServices_1.AdministradorService(prisma_1.prisma, administradorId);
                const out = await service.eliminarCompromiso(id);
                res.json(out);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.AdministradorController = AdministradorController;
