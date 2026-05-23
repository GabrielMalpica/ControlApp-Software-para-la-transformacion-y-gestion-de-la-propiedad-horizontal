// src/routes/operarios.ts
import { Router } from "express";
import { OperarioController } from "../controller/OperarioController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const controller = new OperarioController();

router.use(authRequired);
router.use(requireRoles("operario"));

// Tareas del operario
router.post(
  "/operarios/:operarioId/tareas/asignar",
  requirePermission("tareas.cerrar"),
  controller.asignarTarea,
);
router.post(
  "/operarios/:operarioId/tareas/:tareaId/iniciar",
  requirePermission("tareas.cerrar"),
  controller.iniciarTarea,
);
router.post(
  "/operarios/:operarioId/tareas/completar",
  requirePermission("tareas.cerrar"),
  controller.marcarComoCompletada,
);
router.post(
  "/operarios/:operarioId/tareas/:tareaId/cerrar",
  requirePermission("tareas.cerrar"),
  uploadEvidencias.array("files", 10),
  controller.cerrarTareaConEvidencias,
);
router.post(
  "/operarios/:operarioId/tareas/:tareaId/no-completada",
  requirePermission("tareas.cerrar"),
  controller.marcarComoNoCompletada,
);

router.get(
  "/operarios/:operarioId/tareas/dia",
  requirePermission("tareas.ver"),
  controller.tareasDelDia,
);
router.get(
  "/operarios/:operarioId/tareas",
  requirePermission("tareas.ver"),
  controller.listarTareas,
);

// Horas
router.get(
  "/operarios/:operarioId/horas/restantes",
  requirePermission("tareas.ver"),
  controller.horasRestantesEnSemana,
);
router.get(
  "/operarios/:operarioId/horas/resumen",
  requirePermission("tareas.ver"),
  controller.resumenDeHoras,
);

export default router;
