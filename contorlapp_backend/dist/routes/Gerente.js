"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/gerente.routes.ts
const express_1 = require("express");
const CompromisoConjuntoController_1 = require("../controller/CompromisoConjuntoController");
const GerenteController_1 = require("../controller/GerenteController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const router = (0, express_1.Router)();
const ctrl = new GerenteController_1.GerenteController();
const compromisosCtrl = new CompromisoConjuntoController_1.CompromisoConjuntoController();
/* Empresa */
router.post("/empresa", ctrl.crearEmpresa);
router.patch("/empresa/limite-horas", ctrl.actualizarLimiteHoras); // opcional
/* Usuarios */
router.post("/usuarios", ctrl.crearUsuario);
router.put("/usuarios/:id", ctrl.editarUsuario);
router.get("/usuarios", ctrl.listarUsuarios);
router.delete("/usuarios/:id", ctrl.eliminarUsuario);
/* Roles / perfiles */
router.post("/gerentes", ctrl.asignarGerente);
router.post("/administradores", ctrl.asignarAdministrador);
router.post("/jefes-operaciones", ctrl.asignarJefeOperaciones);
router.post("/supervisores", ctrl.asignarSupervisor);
router.post("/operarios", ctrl.asignarOperario);
router.get("/supervisores", ctrl.listarSupervisores);
/* Conjuntos */
router.post("/conjuntos", ctrl.crearConjunto);
router.patch("/conjuntos/:conjuntoId", ctrl.editarConjunto);
router.get("/conjuntos", ctrl.listarConjuntos);
router.get("/conjuntos/:conjuntoId", ctrl.obtenerConjunto);
router.post("/conjuntos/:conjuntoId/operarios", ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", ctrl.agregarInsumoAConjunto);
router.get("/conjuntos/:conjuntoId/compromisos", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), compromisosCtrl.listarPorConjunto);
router.post("/conjuntos/:conjuntoId/compromisos", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), compromisosCtrl.crear);
/* Compromisos */
router.get("/compromisos", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), compromisosCtrl.listarGlobal);
router.patch("/compromisos/:id", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), compromisosCtrl.actualizar);
router.delete("/compromisos/:id", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones", "supervisor"), compromisosCtrl.eliminar);
/* Tareas */
router.post("/tareas", ctrl.asignarTarea);
router.post("/tareas/reemplazo", ctrl.asignarTareaConReemplazo);
router.patch("/tareas/:tareaId", ctrl.editarTarea);
router.get("/conjuntos/:conjuntoId/tareas", ctrl.listarTareasPorConjunto);
/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", ctrl.reemplazarAdminEnVariosConjuntos);
router.delete("/operarios/:operarioId", ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", ctrl.eliminarSupervisor);
router.delete("/conjuntos/:conjuntoId", ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", ctrl.eliminarMaquinaria);
router.delete("/tareas/:tareaId", ctrl.eliminarTarea);
/* Ediciones rápidas */
router.patch("/administradores/:adminId", ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", ctrl.editarSupervisor);
exports.default = router;
