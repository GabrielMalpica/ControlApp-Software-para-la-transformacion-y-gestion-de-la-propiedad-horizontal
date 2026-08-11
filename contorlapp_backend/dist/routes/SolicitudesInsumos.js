"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudesInsumos.ts
const express_1 = require("express");
const SolicitudInsumoController_1 = require("../controller/SolicitudInsumoController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new SolicitudInsumoController_1.SolicitudInsumoController();
router.use(auth_middleware_1.authRequired);
router.post("/", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireBodyConjuntoScope)(), controller.crear);
router.get("/", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.listar);
router.get("/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudInsumo", "id"), controller.obtener);
router.post("/:id/aprobar", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudInsumo", "id"), controller.aprobar);
router.delete("/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudInsumo", "id"), controller.eliminar);
exports.default = router;
