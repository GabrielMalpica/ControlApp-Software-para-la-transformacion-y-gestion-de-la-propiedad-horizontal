"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudes-tarea.ts
const express_1 = require("express");
const SolicitudTareaController_1 = require("../controller/SolicitudTareaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new SolicitudTareaController_1.SolicitudTareaController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"));
router.post("/solicitudes-tarea/:solicitudId/aprobar", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudTarea", "solicitudId"), controller.aprobar);
router.post("/solicitudes-tarea/:solicitudId/rechazar", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudTarea", "solicitudId"), controller.rechazar);
router.get("/solicitudes-tarea/:solicitudId/estado", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireResourceScope)("solicitudTarea", "solicitudId"), controller.estadoActual);
exports.default = router;
