"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// ejemplo: src/routes/Inventario.ts
const express_1 = require("express");
const InventarioController_1 = require("../controller/InventarioController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const c = new InventarioController_1.InventarioController();
router.use(auth_middleware_1.authRequired);
// ✅ por conjunto
router.get("/conjunto/:nit/insumos", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireConjuntoScope)("nit"), c.listarInsumosConjunto);
router.get("/conjunto/:nit/insumos-bajos", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireConjuntoScope)("nit"), c.listarInsumosBajosConjunto);
router.post("/conjunto/:nit/agregar-stock", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("nit"), c.agregarStockConjunto);
router.post("/conjunto/:nit/consumir-stock", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("nit"), c.consumirStockConjunto);
router.get("/conjunto/:nit/insumos/:insumoId", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireConjuntoScope)("nit"), c.buscarInsumoConjunto);
// ✅ legacy por inventarioId (si aún los usas)
router.post("/:inventarioId/insumos", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.agregarInsumo);
router.get("/:inventarioId/insumos", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.listarInsumos);
router.delete("/:inventarioId/insumos/:insumoId", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.eliminarInsumo);
router.get("/:inventarioId/insumos/:insumoId", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.buscarInsumoPorId);
router.post("/:inventarioId/insumos/:insumoId/consumir", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.consumirInsumoPorId);
router.get("/:inventarioId/insumos-bajos", (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireResourceScope)("inventario", "inventarioId"), c.listarInsumosBajos);
exports.default = router;
