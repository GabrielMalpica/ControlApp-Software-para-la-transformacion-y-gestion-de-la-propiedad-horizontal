"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// ejemplo: src/routes/Inventario.ts
const express_1 = require("express");
const InventarioController_1 = require("../controller/InventarioController");
const router = (0, express_1.Router)();
const c = new InventarioController_1.InventarioController();
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
exports.default = router;
