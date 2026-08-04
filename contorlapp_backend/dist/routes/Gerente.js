"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/gerente.routes.ts
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const CompromisoConjuntoController_1 = require("../controller/CompromisoConjuntoController");
const GerenteController_1 = require("../controller/GerenteController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const router = (0, express_1.Router)();
const ctrl = new GerenteController_1.GerenteController();
const compromisosCtrl = new CompromisoConjuntoController_1.CompromisoConjuntoController();
const uploadResidentes = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024, files: 1 },
    fileFilter: (_req, file, cb) => {
        const mime = String(file.mimetype ?? "").toLowerCase();
        const name = String(file.originalname ?? "").toLowerCase();
        const isExcel = mime.includes("sheet") ||
            mime.includes("excel") ||
            name.endsWith(".xlsx") ||
            name.endsWith(".csv");
        if (!isExcel) {
            cb(new Error("Solo se permiten archivos Excel (.xlsx) o CSV para cargar residentes."));
            return;
        }
        cb(null, true);
    },
});
const uploadConjuntos = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
    limits: { fileSize: 10 * 1024 * 1024, files: 1 },
    fileFilter: (_req, file, cb) => {
        const mime = String(file.mimetype ?? "").toLowerCase();
        const name = String(file.originalname ?? "").toLowerCase();
        const isXlsx = mime.includes("spreadsheetml") ||
            mime.includes("sheet") ||
            name.endsWith(".xlsx");
        if (!isXlsx || !name.endsWith(".xlsx")) {
            cb(new Error("Solo se permiten plantillas Excel (.xlsx) para cargar conjuntos."));
            return;
        }
        cb(null, true);
    },
});
/* Empresa */
router.get("/permisos", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente"), ctrl.obtenerCatalogoPermisos);
router.put("/permisos", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente"), ctrl.actualizarMatrizPermisos);
router.post("/empresa", ctrl.crearEmpresa);
router.patch("/empresa/limite-horas", ctrl.actualizarLimiteHoras); // opcional
/* Usuarios */
router.post("/usuarios", ctrl.crearUsuario);
router.put("/usuarios/:id", ctrl.editarUsuario);
router.get("/usuarios", ctrl.listarUsuarios);
router.delete("/usuarios/:id", ctrl.eliminarUsuario);
router.post("/residentes", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("residentes.crear"), ctrl.crearResidenteManual);
router.get("/residentes", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("residentes.ver"), ctrl.listarResidentes);
router.put("/residentes/:residenteId", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("residentes.editar"), ctrl.editarResidente);
router.delete("/residentes/:residenteId", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("residentes.eliminar"), ctrl.eliminarResidenteGestion);
router.post("/residentes/carga-masiva", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("residentes.cargar_masivo"), uploadResidentes.single("file"), ctrl.cargarResidentesMasivo);
/* Roles / perfiles */
router.post("/gerentes", ctrl.asignarGerente);
router.post("/administradores", ctrl.asignarAdministrador);
router.post("/jefes-operaciones", ctrl.asignarJefeOperaciones);
router.post("/supervisores", ctrl.asignarSupervisor);
router.post("/operarios", ctrl.asignarOperario);
router.get("/supervisores", ctrl.listarSupervisores);
/* Conjuntos */
router.post("/conjuntos", ctrl.crearConjunto);
router.post("/conjuntos/carga-masiva", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente"), uploadConjuntos.single("file"), ctrl.cargarConjuntoMasivo);
router.get("/conjuntos/plantilla", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente"), ctrl.descargarPlantillaConjunto);
router.patch("/conjuntos/:conjuntoId", ctrl.editarConjunto);
router.get("/conjuntos", ctrl.listarConjuntos);
router.get("/conjuntos/:conjuntoId", ctrl.obtenerConjunto);
router.post("/conjuntos/:conjuntoId/operarios", ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", ctrl.agregarInsumoAConjunto);
router.get("/conjuntos/:conjuntoId/compromisos", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("compromisos.ver"), compromisosCtrl.listarPorConjunto);
router.post("/conjuntos/:conjuntoId/compromisos", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), compromisosCtrl.crear);
/* Compromisos */
router.get("/compromisos", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("compromisos.globales_ver"), compromisosCtrl.listarGlobal);
router.patch("/compromisos/:id", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), compromisosCtrl.actualizar);
router.delete("/compromisos/:id", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), compromisosCtrl.eliminar);
/* Tareas */
router.post("/tareas", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), ctrl.asignarTarea);
router.post("/tareas/reemplazo", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), ctrl.asignarTareaConReemplazo);
router.patch("/tareas/:tareaId", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), ctrl.editarTarea);
router.get("/conjuntos/:conjuntoId/tareas", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("tareas.ver"), ctrl.listarTareasPorConjunto);
/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", ctrl.reemplazarAdminEnVariosConjuntos);
router.delete("/operarios/:operarioId", ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", ctrl.eliminarSupervisor);
router.delete("/conjuntos/:conjuntoId", ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", ctrl.eliminarMaquinaria);
router.delete("/tareas/:tareaId", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("tareas.crear"), ctrl.eliminarTarea);
/* Ediciones rápidas */
router.patch("/administradores/:adminId", ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", ctrl.editarSupervisor);
exports.default = router;
