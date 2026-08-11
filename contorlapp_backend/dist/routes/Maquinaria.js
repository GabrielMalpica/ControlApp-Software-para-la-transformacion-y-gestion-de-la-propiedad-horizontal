"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/maquinarias.ts
const express_1 = require("express");
const MaquinariaController_1 = require("../controller/MaquinariaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new MaquinariaController_1.MaquinariaController();
router.use(auth_middleware_1.authRequired);
// Asignación y devolución
router.post("/:maquinariaId/asignar", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), controller.asignarAConjunto);
router.post("/:maquinariaId/devolver", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), controller.devolver);
// Consultas rápidas
router.get("/:maquinariaId/disponible", (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), controller.estaDisponible);
router.get("/:maquinariaId/responsable", (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), controller.obtenerResponsable);
router.get("/:maquinariaId/resumen", (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), controller.resumenEstado);
router.get("/:maquinariaId/agenda/:conjuntoId", (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), controller.agendaMaquinaria);
exports.default = router;
