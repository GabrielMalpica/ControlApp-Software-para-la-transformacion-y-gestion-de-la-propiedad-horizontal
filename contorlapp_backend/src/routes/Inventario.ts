// ejemplo: src/routes/Inventario.ts
import { Router } from "express";
import { InventarioController } from "../controller/InventarioController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const c = new InventarioController();

router.use(authRequired);

// ✅ por conjunto
router.get("/conjunto/:nit/insumos", requirePermission("inventario.ver"), requireConjuntoScope("nit"), c.listarInsumosConjunto);
router.get(
  "/conjunto/:nit/insumos-bajos",
  requirePermission("inventario.ver"),
  requireConjuntoScope("nit"),
  c.listarInsumosBajosConjunto,
);
router.post("/conjunto/:nit/agregar-stock", requirePermission("inventario.gestionar"), requireConjuntoScope("nit"), c.agregarStockConjunto);
router.post(
  "/conjunto/:nit/consumir-stock",
  requirePermission("inventario.gestionar"),
  requireConjuntoScope("nit"),
  c.consumirStockConjunto,
);
router.get("/conjunto/:nit/insumos/:insumoId", requirePermission("inventario.ver"), requireConjuntoScope("nit"), c.buscarInsumoConjunto);

// ✅ legacy por inventarioId (si aún los usas)
router.post("/:inventarioId/insumos", requirePermission("inventario.gestionar"), requireResourceScope("inventario", "inventarioId"), c.agregarInsumo);
router.get("/:inventarioId/insumos", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.listarInsumos);
router.delete("/:inventarioId/insumos/:insumoId", requirePermission("inventario.gestionar"), requireResourceScope("inventario", "inventarioId"), c.eliminarInsumo);
router.get("/:inventarioId/insumos/:insumoId", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.buscarInsumoPorId);
router.post(
  "/:inventarioId/insumos/:insumoId/consumir",
  requirePermission("inventario.gestionar"),
  requireResourceScope("inventario", "inventarioId"),
  c.consumirInsumoPorId,
);
router.get("/:inventarioId/insumos-bajos", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.listarInsumosBajos);

export default router;
