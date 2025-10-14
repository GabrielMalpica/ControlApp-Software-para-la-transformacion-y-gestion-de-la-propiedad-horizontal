// src/routes/inventarios.ts
import { Router } from "express";
import { InventarioController } from "../controller/InventarioController";

const router = Router();
const controller = new InventarioController();

// CRUD de insumos en un inventario
router.post("/inventarios/:inventarioId/insumos", controller.agregarInsumo);
router.get("/inventarios/:inventarioId/insumos", controller.listarInsumos);
router.get("/inventarios/:inventarioId/insumos/:insumoId", controller.buscarInsumoPorId);
router.delete("/inventarios/:inventarioId/insumos/:insumoId", controller.eliminarInsumo);

// Consumo
router.post("/inventarios/:inventarioId/insumos/:insumoId/consumir", controller.consumirInsumoPorId);

// Reporte de bajos
router.get("/inventarios/:inventarioId/insumos-bajos", controller.listarInsumosBajos);

export default router;
