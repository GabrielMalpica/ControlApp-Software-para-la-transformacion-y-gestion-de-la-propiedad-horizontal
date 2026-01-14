// ejemplo: src/routes/Inventario.ts
import { Router } from "express";
import { PrismaClient } from "../generated/prisma";
import { InventarioController } from "../controller/InventarioController";

const router = Router();
const prisma = new PrismaClient();
const c = new InventarioController(prisma);

// ✅ por conjunto
router.get("/conjunto/:nit/insumos", c.listarInsumosConjunto);
router.get("/conjunto/:nit/insumos-bajos", c.listarInsumosBajosConjunto);
router.post("/conjunto/:nit/agregar-stock", c.agregarStockConjunto);
router.post("/conjunto/:nit/consumir-stock", c.consumirStockConjunto);
router.get("/conjunto/:nit/insumos/:insumoId", c.buscarInsumoConjunto);

// ✅ legacy por inventarioId (si aún los usas)
router.post("/:inventarioId/insumos", c.agregarInsumo);
router.get("/:inventarioId/insumos", c.listarInsumos);
router.delete("/:inventarioId/insumos/:insumoId", c.eliminarInsumo);
router.get("/:inventarioId/insumos/:insumoId", c.buscarInsumoPorId);
router.post("/:inventarioId/insumos/:insumoId/consumir", c.consumirInsumoPorId);
router.get("/:inventarioId/insumos-bajos", c.listarInsumosBajos);

export default router;
