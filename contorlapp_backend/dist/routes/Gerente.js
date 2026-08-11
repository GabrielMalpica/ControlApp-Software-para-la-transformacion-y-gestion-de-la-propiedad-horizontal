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
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
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
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("gerente"));
/* Empresa */
router.get("/permisos", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.obtenerCatalogoPermisos);
router.put("/permisos", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.actualizarMatrizPermisos);
router.post("/empresa", (0, permission_middleware_1.requirePermission)("empresa.gestionar"), ctrl.crearEmpresa);
router.patch("/empresa/limite-horas", (0, permission_middleware_1.requirePermission)("empresa.gestionar"), ctrl.actualizarLimiteHoras);
/* Usuarios */
router.post("/usuarios", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.crearUsuario);
router.put("/usuarios/:id", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("usuario", "id"), ctrl.editarUsuario);
router.get("/usuarios", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.listarUsuarios);
router.delete("/usuarios/:id", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("usuario", "id"), ctrl.eliminarUsuario);
router.post("/residentes", (0, permission_middleware_1.requirePermission)("residentes.crear"), ctrl.crearResidenteManual);
router.get("/residentes", (0, permission_middleware_1.requirePermission)("residentes.ver"), ctrl.listarResidentes);
router.put("/residentes/:residenteId", (0, permission_middleware_1.requirePermission)("residentes.editar"), (0, tenant_middleware_1.requireResourceScope)("residente", "residenteId"), ctrl.editarResidente);
router.delete("/residentes/:residenteId", (0, permission_middleware_1.requirePermission)("residentes.eliminar"), (0, tenant_middleware_1.requireResourceScope)("residente", "residenteId"), ctrl.eliminarResidenteGestion);
router.post("/residentes/carga-masiva", (0, permission_middleware_1.requirePermission)("residentes.cargar_masivo"), uploadResidentes.single("file"), ctrl.cargarResidentesMasivo);
/* Roles / perfiles */
router.post("/gerentes", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.asignarGerente);
router.post("/administradores", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.asignarAdministrador);
router.post("/jefes-operaciones", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.asignarJefeOperaciones);
router.post("/supervisores", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.asignarSupervisor);
router.post("/operarios", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.asignarOperario);
router.get("/supervisores", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.listarSupervisores);
/* Conjuntos */
router.post("/conjuntos", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), ctrl.crearConjunto);
router.post("/conjuntos/carga-masiva", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), uploadConjuntos.single("file"), ctrl.cargarConjuntoMasivo);
router.get("/conjuntos/plantilla", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), ctrl.descargarPlantillaConjunto);
router.patch("/conjuntos/:conjuntoId", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.editarConjunto);
router.get("/conjuntos", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), ctrl.listarConjuntos);
router.get("/conjuntos/:conjuntoId", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.obtenerConjunto);
router.post("/conjuntos/:conjuntoId/operarios", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", (0, permission_middleware_1.requirePermission)("inventario.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.agregarInsumoAConjunto);
router.get("/conjuntos/:conjuntoId/compromisos", (0, permission_middleware_1.requirePermission)("compromisos.ver"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), compromisosCtrl.listarPorConjunto);
router.post("/conjuntos/:conjuntoId/compromisos", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), compromisosCtrl.crear);
/* Compromisos */
router.get("/compromisos", (0, permission_middleware_1.requirePermission)("compromisos.globales_ver"), compromisosCtrl.listarGlobal);
router.patch("/compromisos/:id", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireResourceScope)("compromiso", "id"), compromisosCtrl.actualizar);
router.delete("/compromisos/:id", (0, permission_middleware_1.requirePermission)("compromisos.gestionar"), (0, tenant_middleware_1.requireResourceScope)("compromiso", "id"), compromisosCtrl.eliminar);
/* Tareas */
router.post("/tareas", (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), ctrl.asignarTarea);
router.post("/tareas/reemplazo", (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), ctrl.asignarTareaConReemplazo);
router.patch("/tareas/:tareaId", (0, permission_middleware_1.requirePermission)("tareas.crear", "cronograma.correctivas_programar"), (0, tenant_middleware_1.requireResourceScope)("tarea", "tareaId"), ctrl.editarTarea);
router.get("/conjuntos/:conjuntoId/tareas", (0, permission_middleware_1.requirePermission)("tareas.ver"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.listarTareasPorConjunto);
/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("administrador", "adminId"), ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), ctrl.reemplazarAdminEnVariosConjuntos);
router.delete("/operarios/:operarioId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("operario", "operarioId"), ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("supervisor", "supervisorId"), ctrl.eliminarSupervisor);
router.delete("/conjuntos/:conjuntoId", (0, permission_middleware_1.requirePermission)("conjuntos.gestionar"), (0, tenant_middleware_1.requireConjuntoScope)("conjuntoId"), ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", (0, permission_middleware_1.requirePermission)("maquinaria.asignar"), (0, tenant_middleware_1.requireResourceScope)("maquinaria", "maquinariaId"), ctrl.eliminarMaquinaria);
router.delete("/tareas/:tareaId", (0, permission_middleware_1.requirePermission)("tareas.crear"), (0, tenant_middleware_1.requireResourceScope)("tarea", "tareaId"), ctrl.eliminarTarea);
/* Ediciones rápidas */
router.patch("/administradores/:adminId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("administrador", "adminId"), ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("operario", "operarioId"), ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", (0, permission_middleware_1.requirePermission)("usuarios.gestionar"), (0, tenant_middleware_1.requireResourceScope)("supervisor", "supervisorId"), ctrl.editarSupervisor);
exports.default = router;
