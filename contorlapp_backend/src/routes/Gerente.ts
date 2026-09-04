// src/routes/gerente.routes.ts
import { Router } from "express";
import multer from "multer";
import { CompromisoConjuntoController } from "../controller/CompromisoConjuntoController";
import { GerenteController } from "../controller/GerenteController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { PermissionService } from "../services/PermissionService";
import {
  requireConjuntoScope,
  requireResourceScope,
} from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new GerenteController();
const compromisosCtrl = new CompromisoConjuntoController();
const anyConfiguredPermission = PermissionService.catalog().map(
  (permission) => permission.key,
);
const uploadResidentes = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    const mime = String(file.mimetype ?? "").toLowerCase();
    const name = String(file.originalname ?? "").toLowerCase();
    const isExcel =
      mime.includes("sheet") ||
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
const uploadConjuntos = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    const mime = String(file.mimetype ?? "").toLowerCase();
    const name = String(file.originalname ?? "").toLowerCase();
    const isXlsx =
      mime.includes("spreadsheetml") ||
      mime.includes("sheet") ||
      name.endsWith(".xlsx");

    if (!isXlsx || !name.endsWith(".xlsx")) {
      cb(new Error("Solo se permiten plantillas Excel (.xlsx) para cargar conjuntos."));
      return;
    }
    cb(null, true);
  },
});

router.use(authRequired);

// Este router conserva el nombre historico "/gerente", pero sus recursos
// operativos se autorizan por permiso. Un gate global de rol aqui hacia que
// la matriz mostrara accesos habilitados para otros perfiles y luego los
// rechazara antes de evaluar requirePermission.
//
// Las operaciones exclusivas del gerente mantienen un gate de rol en la
// ruta concreta. La plantilla debe ir antes de "/conjuntos/:conjuntoId".
router.get(
  "/conjuntos-selector",
  requirePermission(...anyConfiguredPermission),
  ctrl.listarConjuntosSelector,
);
router.get(
  "/conjuntos/plantilla",
  requirePermission("conjuntos.gestionar"),
  ctrl.descargarPlantillaConjunto,
);
router.get(
  "/conjuntos",
  requirePermission("conjuntos.ver", "conjuntos.gestionar"),
  ctrl.listarConjuntos,
);
router.get(
  "/conjuntos/:conjuntoId",
  requirePermission("conjuntos.ver", "conjuntos.gestionar"),
  requireConjuntoScope("conjuntoId"),
  ctrl.obtenerConjunto,
);

/* Empresa */
router.get(
  "/permisos",
  requireRoles("gerente"),
  requirePermission("usuarios.gestionar"),
  ctrl.obtenerCatalogoPermisos,
);
router.put(
  "/permisos",
  requireRoles("gerente"),
  requirePermission("usuarios.gestionar"),
  ctrl.actualizarMatrizPermisos,
);

router.post(
  "/empresa",
  requireRoles("gerente"),
  requirePermission("empresa.gestionar"),
  ctrl.crearEmpresa,
);
router.patch(
  "/empresa/limite-horas",
  requirePermission("empresa.gestionar"),
  ctrl.actualizarLimiteHoras,
);

/* Usuarios */
router.post("/usuarios", requirePermission("usuarios.gestionar"), ctrl.crearUsuario);
router.put(
  "/usuarios/:id",
  requirePermission("usuarios.gestionar"),
  requireResourceScope("usuario", "id"),
  ctrl.editarUsuario,
);
router.get("/usuarios", requirePermission("usuarios.gestionar"), ctrl.listarUsuarios);
router.delete(
  "/usuarios/:id",
  requirePermission("usuarios.gestionar"),
  requireResourceScope("usuario", "id"),
  ctrl.eliminarUsuario,
);
router.post(
  "/residentes",
  requirePermission("residentes.crear"),
  ctrl.crearResidenteManual,
);
router.get(
  "/residentes",
  requirePermission("residentes.ver"),
  ctrl.listarResidentes,
);
router.put(
  "/residentes/:residenteId",
  requirePermission("residentes.editar"),
  requireResourceScope("residente", "residenteId"),
  ctrl.editarResidente,
);
router.delete(
  "/residentes/:residenteId",
  requirePermission("residentes.eliminar"),
  requireResourceScope("residente", "residenteId"),
  ctrl.eliminarResidenteGestion,
);
router.post(
  "/residentes/carga-masiva",
  requirePermission("residentes.cargar_masivo"),
  uploadResidentes.single("file"),
  ctrl.cargarResidentesMasivo,
);

/* Roles / perfiles */
router.post("/gerentes", requirePermission("usuarios.gestionar"), ctrl.asignarGerente);
router.post("/administradores", requirePermission("usuarios.gestionar"), ctrl.asignarAdministrador);
router.post("/jefes-operaciones", requirePermission("usuarios.gestionar"), ctrl.asignarJefeOperaciones);
router.post("/supervisores", requirePermission("usuarios.gestionar"), ctrl.asignarSupervisor);
router.post("/operarios", requirePermission("usuarios.gestionar"), ctrl.asignarOperario);
router.get("/supervisores", requirePermission("usuarios.gestionar"), ctrl.listarSupervisores);

/* Conjuntos */
// GET /conjuntos, GET /conjuntos/plantilla y GET /conjuntos/:conjuntoId se
// registran mas arriba para respetar el orden de las rutas.
router.post("/conjuntos", requirePermission("conjuntos.gestionar"), ctrl.crearConjunto);
router.post(
  "/conjuntos/carga-masiva",
  requirePermission("conjuntos.gestionar"),
  uploadConjuntos.single("file"),
  ctrl.cargarConjuntoMasivo,
);
router.patch("/conjuntos/:conjuntoId", requirePermission("conjuntos.gestionar"), requireConjuntoScope("conjuntoId"), ctrl.editarConjunto);
router.post("/conjuntos/:conjuntoId/operarios", requirePermission("conjuntos.gestionar"), requireConjuntoScope("conjuntoId"), ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", requirePermission("inventario.gestionar"), requireConjuntoScope("conjuntoId"), ctrl.agregarInsumoAConjunto);
router.get(
  "/conjuntos/:conjuntoId/compromisos",
  requirePermission("compromisos.ver"),
  requireConjuntoScope("conjuntoId"),
  compromisosCtrl.listarPorConjunto,
);
router.post(
  "/conjuntos/:conjuntoId/compromisos",
  requirePermission("compromisos.gestionar"),
  requireConjuntoScope("conjuntoId"),
  compromisosCtrl.crear,
);

/* Compromisos */
router.get(
  "/compromisos",
  requirePermission("compromisos.globales_ver"),
  compromisosCtrl.listarGlobal,
);
router.patch(
  "/compromisos/:id",
  requirePermission("compromisos.gestionar"),
  requireResourceScope("compromiso", "id"),
  compromisosCtrl.actualizar,
);
router.delete(
  "/compromisos/:id",
  requirePermission("compromisos.gestionar"),
  requireResourceScope("compromiso", "id"),
  compromisosCtrl.eliminar,
);

/* Tareas */
router.post(
  "/tareas",
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  ctrl.asignarTarea,
);
router.post(
  "/tareas/reemplazo",
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  ctrl.asignarTareaConReemplazo,
);
router.patch(
  "/tareas/:tareaId",
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  requireResourceScope("tarea", "tareaId"),
  ctrl.editarTarea,
);
router.get(
  "/conjuntos/:conjuntoId/tareas",
  requirePermission("tareas.ver"),
  requireConjuntoScope("conjuntoId"),
  ctrl.listarTareasPorConjunto,
);

/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", requirePermission("usuarios.gestionar"), requireResourceScope("administrador", "adminId"), ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", requirePermission("usuarios.gestionar"), ctrl.reemplazarAdminEnVariosConjuntos);

router.delete("/operarios/:operarioId", requirePermission("usuarios.gestionar"), requireResourceScope("operario", "operarioId"), ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", requirePermission("usuarios.gestionar"), requireResourceScope("supervisor", "supervisorId"), ctrl.eliminarSupervisor);

router.delete("/conjuntos/:conjuntoId", requirePermission("conjuntos.gestionar"), requireConjuntoScope("conjuntoId"), ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", requirePermission("maquinaria.asignar"), requireResourceScope("maquinaria", "maquinariaId"), ctrl.eliminarMaquinaria);
router.delete(
  "/tareas/:tareaId",
  requirePermission("tareas.crear"),
  requireResourceScope("tarea", "tareaId"),
  ctrl.eliminarTarea,
);

/* Ediciones rápidas */
router.patch("/administradores/:adminId", requirePermission("usuarios.gestionar"), requireResourceScope("administrador", "adminId"), ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", requirePermission("usuarios.gestionar"), requireResourceScope("operario", "operarioId"), ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", requirePermission("usuarios.gestionar"), requireResourceScope("supervisor", "supervisorId"), ctrl.editarSupervisor);

export default router;
