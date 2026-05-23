"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/operarios.ts
const express_1 = require("express");
const OperarioController_1 = require("../controller/OperarioController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const upload_evidencias_1 = require("../middlewares/upload_evidencias");
const router = (0, express_1.Router)();
const controller = new OperarioController_1.OperarioController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("operario"));
// Tareas del operario
router.post("/operarios/:operarioId/tareas/asignar", (0, permission_middleware_1.requirePermission)("tareas.cerrar"), controller.asignarTarea);
router.post("/operarios/:operarioId/tareas/:tareaId/iniciar", (0, permission_middleware_1.requirePermission)("tareas.cerrar"), controller.iniciarTarea);
router.post("/operarios/:operarioId/tareas/completar", (0, permission_middleware_1.requirePermission)("tareas.cerrar"), controller.marcarComoCompletada);
router.post("/operarios/:operarioId/tareas/:tareaId/cerrar", (0, permission_middleware_1.requirePermission)("tareas.cerrar"), upload_evidencias_1.uploadEvidencias.array("files", 10), controller.cerrarTareaConEvidencias);
router.post("/operarios/:operarioId/tareas/:tareaId/no-completada", (0, permission_middleware_1.requirePermission)("tareas.cerrar"), controller.marcarComoNoCompletada);
router.get("/operarios/:operarioId/tareas/dia", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.tareasDelDia);
router.get("/operarios/:operarioId/tareas", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.listarTareas);
// Horas
router.get("/operarios/:operarioId/horas/restantes", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.horasRestantesEnSemana);
router.get("/operarios/:operarioId/horas/resumen", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.resumenDeHoras);
exports.default = router;
