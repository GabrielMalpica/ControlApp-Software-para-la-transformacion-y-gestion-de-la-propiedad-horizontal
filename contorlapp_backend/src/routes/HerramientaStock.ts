import { Router } from "express";
import { HerramientaStockController } from "../controller/HerramientaStockController";

const router = Router();
const controller = new HerramientaStockController();

// estilo “por conjunto”
router.get("/conjunto/:nit/stock", controller.listarStockConjunto);
router.post("/conjunto/:nit/stock", controller.upsertStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/ajustar", controller.ajustarStockConjunto);
router.delete("/conjunto/:nit/stock/:herramientaId", controller.eliminarStockConjunto);

export default router;
