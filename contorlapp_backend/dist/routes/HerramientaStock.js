"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const HerramientaStockController_1 = require("../controller/HerramientaStockController");
const router = (0, express_1.Router)();
const controller = new HerramientaStockController_1.HerramientaStockController();
// estilo “por conjunto”
router.get("/conjunto/:nit/stock", controller.listarStockConjunto);
router.post("/conjunto/:nit/stock", controller.upsertStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/ajustar", controller.ajustarStockConjunto);
router.delete("/conjunto/:nit/stock/:herramientaId", controller.eliminarStockConjunto);
exports.default = router;
