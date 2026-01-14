// src/controllers/InventarioController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { InventarioService } from "../services/InventarioServices";
import { ConjuntoService } from "../services/ConjuntoServices";
import { decToNumber } from "../utils/decimal";

// ===================== ZOD =====================
const InventarioIdParam = z.object({
  inventarioId: z.coerce.number().int().positive(),
});

const ConjuntoNitParam = z.object({
  nit: z.string().min(3),
});

const InsumoIdParam = z.object({
  insumoId: z.coerce.number().int().positive(),
});

const AgregarInsumoBody = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.coerce.number().positive(),
});

const ConsumirBody = z.object({
  cantidad: z.coerce.number().positive(),
  tareaId: z.number().int().positive().optional(),
  operarioId: z.string().optional(),
  observacion: z.string().optional(),
});

const UmbralQuery = z.object({
  umbral: z.coerce.number().int().min(0).optional(),
  nombre: z.string().optional(),
  categoria: z.string().optional(),
});

// ===================== RESOLVERS =====================

// Resolver inventarioId (acepta header x-inventario-id, query ?inventarioId=, o :inventarioId)
function resolveInventarioId(req: any): number {
  const headerId = req.header?.("x-inventario-id");
  const queryId =
    typeof req.query?.inventarioId === "string" ? req.query.inventarioId : undefined;
  const paramId = req.params?.inventarioId;

  const parsed = InventarioIdParam.safeParse({
    inventarioId: paramId ?? headerId ?? queryId,
  });

  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el inventarioId.");
    e.status = 400;
    throw e;
  }
  return parsed.data.inventarioId;
}

export class InventarioController {
  constructor(private prisma: PrismaClient) {}

  // ==========================================================
  // ✅ NUEVO: ENDPOINTS POR CONJUNTO (para tu front dinámico)
  // ==========================================================

  // GET /inventario/conjunto/:nit/insumos?nombre=&categoria=
  listarInsumosConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const q = UmbralQuery.parse(req.query);

      const service = new ConjuntoService(this.prisma, nit);
      const out = await service.listarInventario({
        nombre: q.nombre,
        categoria: q.categoria,
      });

      res.json(out); // ✅ objetos listos para UI
    } catch (err) {
      next(err);
    }
  };

  // GET /inventario/conjunto/:nit/insumos-bajos?umbral=&nombre=&categoria=
  listarInsumosBajosConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const q = UmbralQuery.parse(req.query);

      const service = new ConjuntoService(this.prisma, nit);
      const out = await service.listarInsumosBajos({
        umbral: q.umbral ?? 5,
        nombre: q.nombre,
        categoria: q.categoria,
      });

      res.json(out); // ✅ objetos listos para UI
    } catch (err) {
      next(err);
    }
  };

  // POST /inventario/conjunto/:nit/agregar-stock
  agregarStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const body = AgregarInsumoBody.parse(req.body);

      const service = new ConjuntoService(this.prisma, nit);
      const out = await service.agregarStock(body);

      res.status(201).json(out ?? { ok: true });
    } catch (err) {
      next(err);
    }
  };

  // POST /inventario/conjunto/:nit/consumir-stock
  consumirStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const body = ConsumirBody.extend({ insumoId: z.number().int().positive() }).parse(req.body);

      const service = new ConjuntoService(this.prisma, nit);
      await service.consumirStock(body);

      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // GET /inventario/conjunto/:nit/insumos/:insumoId
  buscarInsumoConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const { insumoId } = InsumoIdParam.parse(req.params);

      const service = new ConjuntoService(this.prisma, nit);
      const item = await service.buscarInsumoPorId({ insumoId });

      if (!item) {
        res.status(404).json({ message: "Insumo no encontrado en el inventario" });
        return;
      }
      res.json(item);
    } catch (err) {
      next(err);
    }
  };

  // ==========================================================
  // ✅ TUS ENDPOINTS EXISTENTES POR inventarioId (los dejo vivos)
  // ==========================================================

  // POST /inventarios/:inventarioId/insumos
  agregarInsumo: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const service = new InventarioService(this.prisma, inventarioId);
      const body = AgregarInsumoBody.parse(req.body);
      const out = await service.agregarInsumo(body);
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /inventarios/:inventarioId/insumos (✅ ahora devuelve objetos, no strings)
  listarInsumos: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const service = new InventarioService(this.prisma, inventarioId);
      const q = UmbralQuery.parse(req.query);
      const items = await service.listarInsumosDetallado({
        nombre: q.nombre,
        categoria: q.categoria,
      });
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /inventarios/:inventarioId/insumos/:insumoId
  eliminarInsumo: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const service = new InventarioService(this.prisma, inventarioId);
      await service.eliminarInsumo({ insumoId });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // GET /inventarios/:inventarioId/insumos/:insumoId
  buscarInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const service = new InventarioService(this.prisma, inventarioId);
      const item = await service.buscarInsumoPorId({ insumoId });
      if (!item) {
        res.status(404).json({ message: "Insumo no encontrado en el inventario" });
        return;
      }
      res.json(item);
    } catch (err) {
      next(err);
    }
  };

  // POST /inventarios/:inventarioId/insumos/:insumoId/consumir
  consumirInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const body = ConsumirBody.parse(req.body);

      const service = new InventarioService(this.prisma, inventarioId);
      await service.consumirInsumoPorId({
        insumoId,
        cantidad: body.cantidad,
        tareaId: body.tareaId,
        operarioId: body.operarioId,
        observacion: body.observacion,
      });

      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // GET /inventarios/:inventarioId/insumos-bajos?umbral=&nombre=&categoria=
  listarInsumosBajos: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const q = UmbralQuery.parse(req.query);

      const service = new InventarioService(this.prisma, inventarioId);
      const list = await service.listarInsumosBajos({
        umbral: q.umbral ?? 5,
        nombre: q.nombre,
        categoria: q.categoria,
      });

      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  // (opcional legacy) /inventarios/:inventarioId/insumos-bajos/detalle
  listarInsumosBajosDetallado: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const q = UmbralQuery.parse(req.query);

      const rows = await this.prisma.inventarioInsumo.findMany({
        where: { inventarioId },
        include: { insumo: true },
      });

      const th = q.umbral ?? 5;

      const bajos = rows
        .filter((r) => decToNumber(r.cantidad) <= th)
        .map((r) => ({
          insumoId: r.insumoId,
          nombre: r.insumo.nombre,
          unidad: r.insumo.unidad,
          cantidad: decToNumber(r.cantidad),
          umbralUsado: th,
          categoria: (r.insumo as any).categoria ?? null,
        }));

      res.json(bajos);
    } catch (err) {
      next(err);
    }
  };
}
