// src/routes/gerente.routes.ts
import { Router } from "express";
import { CompromisoConjuntoController } from "../controller/CompromisoConjuntoController";
import { GerenteController } from "../controller/GerenteController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const ctrl = new GerenteController();
const compromisosCtrl = new CompromisoConjuntoController();

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
