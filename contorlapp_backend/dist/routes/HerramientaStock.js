"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const HerramientaStockController_1 = require("../controller/HerramientaStockController");
const router = (0, express_1.Router)();
const controller = new HerramientaStockController_1.HerramientaStockController();
router.get("/empresa/:empresaId/stock", controller.listarStockEmpresa);
router.post("/empresa/:empresaId/stock", controller.upsertStockEmpresa);
router.patch("/empresa/:empresaId/stock/:herramientaId/ajustar", controller.ajustarStockEmpresa);
router.delete("/empresa/:empresaId/stock/:herramientaId", controller.eliminarStockEmpresa);
// estilo “por conjunto”
router.get("/conjunto/:nit/stock", controller.listarStockConjunto);
router.get("/conjunto/:nit/disponibles", controller.listarDisponibilidadConjunto);
router.post("/conjunto/:nit/stock", controller.upsertStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/ajustar", controller.ajustarStockConjunto);
router.delete("/conjunto/:nit/stock/:herramientaId", controller.eliminarStockConjunto);
router.post("/conjunto/:nit/prestamos/:herramientaId/devolver", controller.devolverPrestamoConjunto);
exports.default = router;
