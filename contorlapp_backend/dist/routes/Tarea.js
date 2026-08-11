"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const TareaController_1 = require("../controller/TareaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new TareaController_1.TareaController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"));
// CRUD
router.post("/", (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), (0, tenant_middleware_1.requireBodyConjuntoScope)(), controller.crearTarea);
router.get("/", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.listarTareas);
router.get("/:id", (0, permission_middleware_1.requirePermission)("tareas.ver"), (0, tenant_middleware_1.requireResourceScope)("tarea", "id"), controller.obtenerTarea);
router.patch("/:id", (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), (0, tenant_middleware_1.requireResourceScope)("tarea", "id"), controller.editarTarea);
router.delete("/:id", (0, permission_middleware_1.requirePermission)("tareas.crear"), (0, tenant_middleware_1.requireResourceScope)("tarea", "id"), controller.eliminarTarea);
exports.default = router;
