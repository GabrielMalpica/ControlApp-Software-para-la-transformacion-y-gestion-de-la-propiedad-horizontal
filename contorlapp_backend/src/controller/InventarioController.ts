// src/controllers/InventarioController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { InventarioService } from "../services/InventarioServices";

// Schemas
const InventarioIdParam = z.object({ inventarioId: z.coerce.number().int().positive() });
const InsumoIdParam = z.object({ insumoId: z.coerce.number().int().positive() });

const AgregarInsumoBody = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const ConsumirBody = z.object({
  cantidad: z.number().int().positive(),
});

const UmbralQuery = z.object({
  umbral: z.coerce.number().int().min(0).optional(),
});

// Resolver inventarioId (acepta header x-inventario-id, query ?inventarioId=, o :inventarioId)
function resolveInventarioId(req: any): number {
  const headerId = req.header?.("x-inventario-id");
  const queryId = typeof req.query?.inventarioId === "string" ? req.query.inventarioId : undefined;
  const paramId = req.params?.inventarioId;
  const parsed = InventarioIdParam.safeParse({ inventarioId: paramId ?? headerId ?? queryId });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el inventarioId.");
    e.status = 400;
    throw e;
  }
  return parsed.data.inventarioId;
}

export class InventarioController {
  constructor(private prisma: PrismaClient) {}

  // POST /inventarios/:inventarioId/insumos
  agregarInsumo: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const service = new InventarioService(this.prisma, inventarioId);
      const body = AgregarInsumoBody.parse(req.body);
      const out = await service.agregarInsumo(body);
      res.status(201).json(out);
    } catch (err) { next(err); }
  };

  // GET /inventarios/:inventarioId/insumos
  listarInsumos: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const service = new InventarioService(this.prisma, inventarioId);
      const items = await service.listarInsumos();
      res.json(items); // devuelve array<string> (tu servicio actual)
    } catch (err) { next(err); }
  };

  // GET /inventarios/:inventarioId/insumos-detalle
  // (opcional) versión para UI con objetos en vez de strings
  listarInsumosDetallado: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      // consulta directa a Prisma para info completa
      const rows = await this.prisma.inventarioInsumo.findMany({
        where: { inventarioId },
        include: { insumo: true },
        orderBy: [{ insumo: { nombre: "asc" } }],
      });
      const data = rows.map(r => ({
        inventarioInsumoId: r.id,
        insumoId: r.insumoId,
        nombre: r.insumo.nombre,
        unidad: r.insumo.unidad,
        categoria: r.insumo.categoria ?? null,
        umbralBajo: r.insumo.umbralBajo ?? null,
        cantidad: r.cantidad,
      }));
      res.json(data);
    } catch (err) { next(err); }
  };

  // DELETE /inventarios/:inventarioId/insumos/:insumoId
  eliminarInsumo: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const service = new InventarioService(this.prisma, inventarioId);
      await service.eliminarInsumo({ insumoId });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /inventarios/:inventarioId/insumos/:insumoId
  buscarInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const service = new InventarioService(this.prisma, inventarioId);
      const item = await service.buscarInsumoPorId({ insumoId });
      if (!item) { res.status(404).json({ message: "Insumo no encontrado en el inventario" }); return; }
      res.json(item);
    } catch (err) { next(err); }
  };

  // POST /inventarios/:inventarioId/insumos/:insumoId/consumir
  consumirInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { insumoId } = InsumoIdParam.parse(req.params);
      const { cantidad } = ConsumirBody.parse(req.body);
      const service = new InventarioService(this.prisma, inventarioId);
      await service.consumirInsumoPorId({ insumoId, cantidad });
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /inventarios/:inventarioId/insumos-bajos?umbral=5
  listarInsumosBajos: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { umbral } = UmbralQuery.parse(req.query);
      const service = new InventarioService(this.prisma, inventarioId);
      const list = await service.listarInsumosBajos(umbral !== undefined ? { umbral } : {});
      res.json(list); // tu servicio devuelve array<string>
    } catch (err) { next(err); }
  };

  // GET /inventarios/:inventarioId/insumos-bajos/detalle?umbral=5
  // (opcional) útil para UI si luego mejoras el service para usar Insumo.umbralBajo
  listarInsumosBajosDetallado: RequestHandler = async (req, res, next) => {
    try {
      const inventarioId = resolveInventarioId(req);
      const { umbral } = UmbralQuery.parse(req.query);
      // consulta detalle y aplica umbral simple (como tu service actual)
      const rows = await this.prisma.inventarioInsumo.findMany({
        where: { inventarioId },
        include: { insumo: true },
      });
      const th = umbral ?? 5;
      const bajos = rows
        .filter(r => r.cantidad <= th)
        .map(r => ({
          insumoId: r.insumoId,
          nombre: r.insumo.nombre,
          unidad: r.insumo.unidad,
          cantidad: r.cantidad,
          umbralUsado: th,
        }));
      res.json(bajos);
    } catch (err) { next(err); }
  };
}
