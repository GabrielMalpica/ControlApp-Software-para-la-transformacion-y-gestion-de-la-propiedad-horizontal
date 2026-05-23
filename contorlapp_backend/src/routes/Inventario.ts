// ejemplo: src/routes/Inventario.ts
import { Router } from "express";
import { InventarioController } from "../controller/InventarioController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const c = new InventarioController();

router.use(authRequired);

// ✅ por conjunto
router.get("/conjunto/:nit/insumos", requirePermission("inventario.ver"), c.listarInsumosConjunto);
router.get(
  "/conjunto/:nit/insumos-bajos",
  requirePermission("inventario.ver"),
  c.listarInsumosBajosConjunto,
);
router.post("/conjunto/:nit/agregar-stock", requirePermission("inventario.ver"), c.agregarStockConjunto);
router.post(
  "/conjunto/:nit/consumir-stock",
  requirePermission("inventario.ver"),
  c.consumirStockConjunto,
);
router.get("/conjunto/:nit/insumos/:insumoId", requirePermission("inventario.ver"), c.buscarInsumoConjunto);

// ✅ legacy por inventarioId (si aún los usas)
router.post("/:inventarioId/insumos", requirePermission("inventario.ver"), c.agregarInsumo);
router.get("/:inventarioId/insumos", requirePermission("inventario.ver"), c.listarInsumos);
router.delete("/:inventarioId/insumos/:insumoId", requirePermission("inventario.ver"), c.eliminarInsumo);
router.get("/:inventarioId/insumos/:insumoId", requirePermission("inventario.ver"), c.buscarInsumoPorId);
router.post(
  "/:inventarioId/insumos/:insumoId/consumir",
  requirePermission("inventario.ver"),
  c.consumirInsumoPorId,
);
router.get("/:inventarioId/insumos-bajos", requirePermission("inventario.ver"), c.listarInsumosBajos);

export default router;
