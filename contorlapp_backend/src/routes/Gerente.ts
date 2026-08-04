// src/routes/gerente.routes.ts
import { Router } from "express";
import multer from "multer";
import { CompromisoConjuntoController } from "../controller/CompromisoConjuntoController";
import { GerenteController } from "../controller/GerenteController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const ctrl = new GerenteController();
const compromisosCtrl = new CompromisoConjuntoController();
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

/* Empresa */
router.get(
  "/permisos",
  authRequired,
  requireRoles("gerente"),
  ctrl.obtenerCatalogoPermisos,
);
router.put(
  "/permisos",
  authRequired,
  requireRoles("gerente"),
  ctrl.actualizarMatrizPermisos,
);

router.post("/empresa", ctrl.crearEmpresa);
router.patch("/empresa/limite-horas", ctrl.actualizarLimiteHoras); // opcional

/* Usuarios */
router.post("/usuarios", ctrl.crearUsuario);
router.put("/usuarios/:id", ctrl.editarUsuario);
router.get("/usuarios", ctrl.listarUsuarios);
router.delete("/usuarios/:id", ctrl.eliminarUsuario);
router.post(
  "/residentes",
  authRequired,
  requirePermission("residentes.crear"),
  ctrl.crearResidenteManual,
);
router.get(
  "/residentes",
  authRequired,
  requirePermission("residentes.ver"),
  ctrl.listarResidentes,
);
router.put(
  "/residentes/:residenteId",
  authRequired,
  requirePermission("residentes.editar"),
  ctrl.editarResidente,
);
router.delete(
  "/residentes/:residenteId",
  authRequired,
  requirePermission("residentes.eliminar"),
  ctrl.eliminarResidenteGestion,
);
router.post(
  "/residentes/carga-masiva",
  authRequired,
  requirePermission("residentes.cargar_masivo"),
  uploadResidentes.single("file"),
  ctrl.cargarResidentesMasivo,
);

/* Roles / perfiles */
router.post("/gerentes", ctrl.asignarGerente);
router.post("/administradores", ctrl.asignarAdministrador);
router.post("/jefes-operaciones", ctrl.asignarJefeOperaciones);
router.post("/supervisores", ctrl.asignarSupervisor);
router.post("/operarios", ctrl.asignarOperario);
router.get("/supervisores", ctrl.listarSupervisores);

/* Conjuntos */
router.post("/conjuntos", ctrl.crearConjunto);
router.post(
  "/conjuntos/carga-masiva",
  authRequired,
  requireRoles("gerente"),
  uploadConjuntos.single("file"),
  ctrl.cargarConjuntoMasivo,
);
router.get(
  "/conjuntos/plantilla",
  authRequired,
  requireRoles("gerente"),
  ctrl.descargarPlantillaConjunto,
);
router.patch("/conjuntos/:conjuntoId", ctrl.editarConjunto);
router.get("/conjuntos", ctrl.listarConjuntos);        
router.get("/conjuntos/:conjuntoId", ctrl.obtenerConjunto); 
router.post("/conjuntos/:conjuntoId/operarios", ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", ctrl.agregarInsumoAConjunto);
router.get(
  "/conjuntos/:conjuntoId/compromisos",
  authRequired,
  requirePermission("compromisos.ver"),
  compromisosCtrl.listarPorConjunto,
);
router.post(
  "/conjuntos/:conjuntoId/compromisos",
  authRequired,
  requirePermission("compromisos.gestionar"),
  compromisosCtrl.crear,
);

/* Compromisos */
router.get(
  "/compromisos",
  authRequired,
  requirePermission("compromisos.globales_ver"),
  compromisosCtrl.listarGlobal,
);
router.patch(
  "/compromisos/:id",
  authRequired,
  requirePermission("compromisos.gestionar"),
  compromisosCtrl.actualizar,
);
router.delete(
  "/compromisos/:id",
  authRequired,
  requirePermission("compromisos.gestionar"),
  compromisosCtrl.eliminar,
);

/* Tareas */
router.post(
  "/tareas",
  authRequired,
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  ctrl.asignarTarea,
);
router.post(
  "/tareas/reemplazo",
  authRequired,
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  ctrl.asignarTareaConReemplazo,
);
router.patch(
  "/tareas/:tareaId",
  authRequired,
  requirePermission("tareas.crear", "cronograma.correctivas_programar"),
  ctrl.editarTarea,
);
router.get(
  "/conjuntos/:conjuntoId/tareas",
  authRequired,
  requirePermission("tareas.ver"),
  ctrl.listarTareasPorConjunto,
);

/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", ctrl.reemplazarAdminEnVariosConjuntos);

router.delete("/operarios/:operarioId", ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", ctrl.eliminarSupervisor);

router.delete("/conjuntos/:conjuntoId", ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", ctrl.eliminarMaquinaria);
router.delete(
  "/tareas/:tareaId",
  authRequired,
  requirePermission("tareas.crear"),
  ctrl.eliminarTarea,
);

/* Ediciones rápidas */
router.patch("/administradores/:adminId", ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", ctrl.editarSupervisor);

export default router;
