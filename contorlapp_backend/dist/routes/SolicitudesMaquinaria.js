"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudesMaquinaria.ts
const express_1 = require("express");
const SolicitudMaquinariaController_1 = require("../controller/SolicitudMaquinariaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const router = (0, express_1.Router)();
const controller = new SolicitudMaquinariaController_1.SolicitudMaquinariaController();
router.use(auth_middleware_1.authRequired);
router.post("/", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.crear);
router.get("/", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.listar);
router.get("/:id", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.obtener);
router.patch("/:id", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.editar);
router.post("/:id/aprobar", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.aprobar);
router.delete("/:id", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), controller.eliminar);
exports.default = router;
