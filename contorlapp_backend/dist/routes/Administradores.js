"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/administradores.ts
const express_1 = require("express");
const AdministradorController_1 = require("../controller/AdministradorController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new AdministradorController_1.AdministradorController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("administrador"));
router.use("/:adminId", (0, tenant_middleware_1.requireSelfScope)("adminId"));
// Conjuntos del administrador
router.get("/:adminId/conjuntos", (0, permission_middleware_1.requirePermission)("compromisos.ver"), controller.verConjuntos);
router.get("/:adminId/conjuntos/:conjuntoId/compromisos", (0, permission_middleware_1.requirePermission)("compromisos.ver"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), controller.listarCompromisosConjunto);
router.post("/:adminId/conjuntos/:conjuntoId/compromisos", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), controller.crearCompromisoConjunto);
router.patch("/:adminId/compromisos/:id", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireResourceScope)("compromiso", "id"), controller.actualizarCompromiso);
router.delete("/:adminId/compromisos/:id", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireResourceScope)("compromiso", "id"), controller.eliminarCompromiso);
// Solicitudes
router.post("/:adminId/solicitudes/tarea", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireBodyConjuntoScope)(), controller.solicitarTarea);
router.post("/:adminId/solicitudes/insumos", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireBodyConjuntoScope)(), controller.solicitarInsumos);
router.post("/:adminId/solicitudes/maquinaria", (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireBodyConjuntoScope)(), controller.solicitarMaquinaria);
exports.default = router;
