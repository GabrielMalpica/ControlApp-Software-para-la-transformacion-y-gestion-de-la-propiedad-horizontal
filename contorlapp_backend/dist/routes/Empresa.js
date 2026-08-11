"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/empresas.ts
const express_1 = require("express");
const EmpresaController_1 = require("../controller/EmpresaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const controller = new EmpresaController_1.EmpresaController();
router.use(auth_middleware_1.authRequired);
// Empresa
router.post("/", (0, role_middleware_1.requireRoles)("gerente"), (0, permission_middleware_1.requirePermission)("empresa.gestionar"), controller.crearEmpresa);
router.get("/:nit/limite-min-semana", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("cronograma.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.getLimiteMinSemanaPorConjunto);
router.get("/festivos", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.listarFestivos);
router.put("/festivos/rango", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.reemplazarFestivosEnRango);
// Maquinaria
router.post("/:nit/maquinaria", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.agregarMaquinaria);
router.get("/:nit/maquinaria/disponible", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.listarMaquinariaDisponible);
router.get("/:nit/maquinaria/prestada", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.obtenerMaquinariaPrestada);
router.get("/:nit/maquinaria", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.listarMaquinariaCatalogo);
router.patch("/:nit/maquinaria/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "id"), controller.editarMaquinaria);
router.delete("/:nit/maquinaria/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "id"), controller.eliminarMaquinaria);
// Jefe de Operaciones
router.post("/:nit/jefe-operaciones", (0, role_middleware_1.requireRoles)("gerente"), (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.agregarJefeOperaciones);
// Solicitudes de tarea
router.patch("/:nit/solicitudes-tarea/:id/recibir", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("solicitudTarea", "id"), controller.recibirSolicitudTarea);
router.delete("/:nit/solicitudes-tarea/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("solicitudTarea", "id"), controller.eliminarSolicitudTarea);
router.get("/:nit/solicitudes-tarea/pendientes", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("solicitudes.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.solicitudesTareaPendientes);
// Catálogo de insumos
router.post("/:nit/catalogo/insumos", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.agregarInsumoAlCatalogo);
router.get("/:nit/catalogo", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), controller.listarCatalogo);
router.get("/:nit/catalogo/insumos/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("inventario.ver"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("insumo", "id"), controller.buscarInsumoPorId);
router.patch("/:nit/catalogo/insumos/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("insumo", "id"), controller.editarInsumoCatalogo);
router.delete("/:nit/catalogo/insumos/:id", (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireEmpresaScope)("nit"), (0, tenant_middleware_1.requireResourceScope)("insumo", "id"), controller.eliminarInsumoCatalogo);
exports.default = router;
