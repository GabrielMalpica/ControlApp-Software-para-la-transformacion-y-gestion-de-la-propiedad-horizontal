"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/ubicaciones.ts
const express_1 = require("express");
const UbicacionController_1 = require("../controller/UbicacionController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new UbicacionController_1.UbicacionController();
router.use(auth_middleware_1.authRequired);
router.post("/ubicaciones/:ubicacionId/elementos", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("mapa_areas.ver"), (0, tenant_middleware_1.requireResourceScope)("ubicacion", "ubicacionId"), controller.agregarElemento);
router.get("/ubicaciones/:ubicacionId/elementos", (0, permission_middleware_1.requirePermission)("mapa_areas.ver"), (0, tenant_middleware_1.requireResourceScope)("ubicacion", "ubicacionId"), controller.listarElementos);
router.get("/ubicaciones/:ubicacionId/elementos/buscar", (0, permission_middleware_1.requirePermission)("mapa_areas.ver"), (0, tenant_middleware_1.requireResourceScope)("ubicacion", "ubicacionId"), controller.buscarElementoPorNombre);
exports.default = router;
