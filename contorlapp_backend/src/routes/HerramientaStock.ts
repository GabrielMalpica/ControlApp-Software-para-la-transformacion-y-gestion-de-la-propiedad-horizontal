import { Router } from "express";
import { HerramientaStockController } from "../controller/HerramientaStockController";

const router = Router();
const controller = new HerramientaStockController();

router.get("/empresa/:empresaId/stock", controller.listarStockEmpresa);
router.post("/empresa/:empresaId/stock", controller.upsertStockEmpresa);
router.patch(
  "/empresa/:empresaId/stock/:herramientaId/ajustar",
  controller.ajustarStockEmpresa,
);
router.patch(
  "/empresa/:empresaId/stock/:herramientaId/estado",
  controller.cambiarEstadoStockEmpresa,
);
router.delete(
  "/empresa/:empresaId/stock/:herramientaId",
  controller.eliminarStockEmpresa,
);

// estilo “por conjunto”
router.get("/conjunto/:nit/stock", controller.listarStockConjunto);
router.get("/conjunto/:nit/disponibles", controller.listarDisponibilidadConjunto);
router.post("/conjunto/:nit/stock", controller.upsertStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/ajustar", controller.ajustarStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/estado", controller.cambiarEstadoStockConjunto);
router.delete("/conjunto/:nit/stock/:herramientaId", controller.eliminarStockConjunto);
router.post(
  "/conjunto/:nit/prestamos/:herramientaId/devolver",
  controller.devolverPrestamoConjunto,
);

export default router;
