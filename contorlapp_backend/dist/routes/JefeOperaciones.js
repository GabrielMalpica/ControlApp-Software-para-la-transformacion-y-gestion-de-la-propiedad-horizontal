"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/jefeOperaciones.routes.ts
const express_1 = require("express");
const JefeOperacionesController_1 = require("../controller/JefeOperacionesController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const upload_evidencias_1 = require("../middlewares/upload_evidencias");
const router = (0, express_1.Router)();
const controller = new JefeOperacionesController_1.JefeOperacionesController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("jefe_operaciones"));
// ✅ Endpoints
router.get("/tareas/pendientes", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.listarPendientes);
// JSON veredicto
router.post("/tareas/:id/veredicto", (0, permission_middleware_1.requirePermission)("tareas.veredicto"), (0, tenant_middleware_1.requireResourceScope)("tarea", "id"), controller.veredicto);
// Multipart veredicto + evidencias
router.post("/tareas/:id/veredicto-multipart", (0, permission_middleware_1.requirePermission)("tareas.veredicto"), (0, tenant_middleware_1.requireResourceScope)("tarea", "id"), upload_evidencias_1.uploadEvidencias.array("files", 10), controller.veredictoMultipart);
exports.default = router;
