import { Router } from "express";
import { HerramientaStockController } from "../controller/HerramientaStockController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireConjuntoScope, requireEmpresaScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new HerramientaStockController();

router.use(authRequired);

router.get("/empresa/:empresaId/stock", requirePermission("herramientas.ver"), requireEmpresaScope("empresaId"), controller.listarStockEmpresa);
router.post("/empresa/:empresaId/stock", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireEmpresaScope("empresaId"), controller.upsertStockEmpresa);
router.patch(
  "/empresa/:empresaId/stock/:herramientaId/ajustar",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("herramientas.gestionar"),
  requireEmpresaScope("empresaId"),
  requireResourceScope("herramienta", "herramientaId"),
  controller.ajustarStockEmpresa,
);
router.patch(
  "/empresa/:empresaId/stock/:herramientaId/estado",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("herramientas.gestionar"),
  requireEmpresaScope("empresaId"),
  requireResourceScope("herramienta", "herramientaId"),
  controller.cambiarEstadoStockEmpresa,
);
router.delete(
  "/empresa/:empresaId/stock/:herramientaId",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("herramientas.gestionar"),
  requireEmpresaScope("empresaId"),
  requireResourceScope("herramienta", "herramientaId"),
  controller.eliminarStockEmpresa,
);

// estilo “por conjunto”
router.get("/conjunto/:nit/stock", requirePermission("herramientas.ver"), requireConjuntoScope("nit"), controller.listarStockConjunto);
router.get("/conjunto/:nit/disponibles", requirePermission("herramientas.ver"), requireConjuntoScope("nit"), controller.listarDisponibilidadConjunto);
router.post("/conjunto/:nit/stock", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireConjuntoScope("nit"), controller.upsertStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/ajustar", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireConjuntoScope("nit"), requireResourceScope("herramienta", "herramientaId"), controller.ajustarStockConjunto);
router.patch("/conjunto/:nit/stock/:herramientaId/estado", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireConjuntoScope("nit"), requireResourceScope("herramienta", "herramientaId"), controller.cambiarEstadoStockConjunto);
router.delete("/conjunto/:nit/stock/:herramientaId", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireConjuntoScope("nit"), requireResourceScope("herramienta", "herramientaId"), controller.eliminarStockConjunto);
router.post(
  "/conjunto/:nit/prestamos/:herramientaId/devolver",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("herramientas.gestionar"),
  requireConjuntoScope("nit"),
  requireResourceScope("herramienta", "herramientaId"),
  controller.devolverPrestamoConjunto,
);

export default router;
