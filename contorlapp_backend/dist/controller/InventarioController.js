"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.InventarioController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const InventarioServices_1 = require("../services/InventarioServices");
const ConjuntoServices_1 = require("../services/ConjuntoServices");
const decimal_1 = require("../utils/decimal");
// ===================== ZOD =====================
const InventarioIdParam = zod_1.z.object({
    inventarioId: zod_1.z.coerce.number().int().positive(),
});
const ConjuntoNitParam = zod_1.z.object({
    nit: zod_1.z.string().min(3),
});
const InsumoIdParam = zod_1.z.object({
    insumoId: zod_1.z.coerce.number().int().positive(),
});
const AgregarInsumoBody = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.coerce.number().positive(),
});
const ConsumirBody = zod_1.z.object({
    cantidad: zod_1.z.coerce.number().positive(),
    tareaId: zod_1.z.number().int().positive().optional(),
    operarioId: zod_1.z.string().optional(),
    observacion: zod_1.z.string().optional(),
});
const UmbralQuery = zod_1.z.object({
    umbral: zod_1.z.coerce.number().int().min(0).optional(),
    nombre: zod_1.z.string().optional(),
    categoria: zod_1.z.string().optional(),
});
// ===================== RESOLVERS =====================
// Resolver inventarioId (acepta header x-inventario-id, query ?inventarioId=, o :inventarioId)
function resolveInventarioId(req) {
    const headerId = req.header?.("x-inventario-id");
    const queryId = typeof req.query?.inventarioId === "string" ? req.query.inventarioId : undefined;
    const paramId = req.params?.inventarioId;
    const parsed = InventarioIdParam.safeParse({
        inventarioId: paramId ?? headerId ?? queryId,
    });
    if (!parsed.success) {
        const e = new Error("Falta o es inválido el inventarioId.");
        e.status = 400;
        throw e;
    }
    return parsed.data.inventarioId;
}
class InventarioController {
    constructor() {
        // ==========================================================
        // ✅ NUEVO: ENDPOINTS POR CONJUNTO (para tu front dinámico)
        // ==========================================================
        // GET /inventario/conjunto/:nit/insumos?nombre=&categoria=
        this.listarInsumosConjunto = async (req, res, next) => {
            try {
                const { nit } = ConjuntoNitParam.parse(req.params);
                const q = UmbralQuery.parse(req.query);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                const out = await service.listarInventario({
                    nombre: q.nombre,
                    categoria: q.categoria,
                });
                res.json(out); // ✅ objetos listos para UI
            }
            catch (err) {
                next(err);
            }
        };
        // GET /inventario/conjunto/:nit/insumos-bajos?umbral=&nombre=&categoria=
        this.listarInsumosBajosConjunto = async (req, res, next) => {
            try {
                const { nit } = ConjuntoNitParam.parse(req.params);
                const q = UmbralQuery.parse(req.query);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                const out = await service.listarInsumosBajos({
                    umbral: q.umbral ?? 5,
                    nombre: q.nombre,
                    categoria: q.categoria,
                });
                res.json(out); // ✅ objetos listos para UI
            }
            catch (err) {
                next(err);
            }
        };
        // POST /inventario/conjunto/:nit/agregar-stock
        this.agregarStockConjunto = async (req, res, next) => {
            try {
                const { nit } = ConjuntoNitParam.parse(req.params);
                const body = AgregarInsumoBody.parse(req.body);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                const out = await service.agregarStock(body);
                res.status(201).json(out ?? { ok: true });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /inventario/conjunto/:nit/consumir-stock
        this.consumirStockConjunto = async (req, res, next) => {
            try {
                const { nit } = ConjuntoNitParam.parse(req.params);
                const body = ConsumirBody.extend({ insumoId: zod_1.z.number().int().positive() }).parse(req.body);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                await service.consumirStock(body);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /inventario/conjunto/:nit/insumos/:insumoId
        this.buscarInsumoConjunto = async (req, res, next) => {
            try {
                const { nit } = ConjuntoNitParam.parse(req.params);
                const { insumoId } = InsumoIdParam.parse(req.params);
                const service = new ConjuntoServices_1.ConjuntoService(prisma_1.prisma, nit);
                const item = await service.buscarInsumoPorId({ insumoId });
                if (!item) {
                    res.status(404).json({ message: "Insumo no encontrado en el inventario" });
                    return;
                }
                res.json(item);
            }
            catch (err) {
                next(err);
            }
        };
        // ==========================================================
        // ✅ TUS ENDPOINTS EXISTENTES POR inventarioId (los dejo vivos)
        // ==========================================================
        // POST /inventarios/:inventarioId/insumos
        this.agregarInsumo = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                const body = AgregarInsumoBody.parse(req.body);
                const out = await service.agregarInsumo(body);
                res.status(201).json(out);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /inventarios/:inventarioId/insumos (✅ ahora devuelve objetos, no strings)
        this.listarInsumos = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                const q = UmbralQuery.parse(req.query);
                const items = await service.listarInsumosDetallado({
                    nombre: q.nombre,
                    categoria: q.categoria,
                });
                res.json(items);
            }
            catch (err) {
                next(err);
            }
        };
        // DELETE /inventarios/:inventarioId/insumos/:insumoId
        this.eliminarInsumo = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const { insumoId } = InsumoIdParam.parse(req.params);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                await service.eliminarInsumo({ insumoId });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /inventarios/:inventarioId/insumos/:insumoId
        this.buscarInsumoPorId = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const { insumoId } = InsumoIdParam.parse(req.params);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                const item = await service.buscarInsumoPorId({ insumoId });
                if (!item) {
                    res.status(404).json({ message: "Insumo no encontrado en el inventario" });
                    return;
                }
                res.json(item);
            }
            catch (err) {
                next(err);
            }
        };
        // POST /inventarios/:inventarioId/insumos/:insumoId/consumir
        this.consumirInsumoPorId = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const { insumoId } = InsumoIdParam.parse(req.params);
                const body = ConsumirBody.parse(req.body);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                await service.consumirInsumoPorId({
                    insumoId,
                    cantidad: body.cantidad,
                    tareaId: body.tareaId,
                    operarioId: body.operarioId,
                    observacion: body.observacion,
                });
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
        // GET /inventarios/:inventarioId/insumos-bajos?umbral=&nombre=&categoria=
        this.listarInsumosBajos = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const q = UmbralQuery.parse(req.query);
                const service = new InventarioServices_1.InventarioService(prisma_1.prisma, inventarioId);
                const list = await service.listarInsumosBajos({
                    umbral: q.umbral ?? 5,
                    nombre: q.nombre,
                    categoria: q.categoria,
                });
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        // (opcional legacy) /inventarios/:inventarioId/insumos-bajos/detalle
        this.listarInsumosBajosDetallado = async (req, res, next) => {
            try {
                const inventarioId = resolveInventarioId(req);
                const q = UmbralQuery.parse(req.query);
                const rows = await prisma_1.prisma.inventarioInsumo.findMany({
                    where: { inventarioId },
                    include: { insumo: true },
                });
                const th = q.umbral ?? 5;
                const bajos = rows
                    .filter((r) => (0, decimal_1.decToNumber)(r.cantidad) <= th)
                    .map((r) => ({
                    insumoId: r.insumoId,
                    nombre: r.insumo.nombre,
                    unidad: r.insumo.unidad,
                    cantidad: (0, decimal_1.decToNumber)(r.cantidad),
                    umbralUsado: th,
                    categoria: r.insumo.categoria ?? null,
                }));
                res.json(bajos);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.InventarioController = InventarioController;
