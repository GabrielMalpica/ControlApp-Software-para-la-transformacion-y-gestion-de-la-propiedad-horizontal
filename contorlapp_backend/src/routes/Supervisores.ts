import { Router } from "express";
import { SupervisorController } from "../controller/SupervisorController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";
import { requireResourceScope } from "../middlewares/tenant.middleware";
import { taskClosingRateLimit } from "../middlewares/task-closing-rate-limit.middleware";

const router = Router();
const ctrl = new SupervisorController();

router.use(authRequired);

router.get(
  "/tareas",
  requirePermission("tareas.ver"),
  ctrl.listarTareas,
);
router.post(
  "/tareas/:id/cerrar",
  requirePermission("tareas.cerrar"),
  requireResourceScope("tarea", "id"),
  taskClosingRateLimit,
  uploadEvidencias.array("files", 10),
  ctrl.cerrarTarea,
);
router.post(
  "/tareas/:id/veredicto",
  requirePermission("tareas.veredicto"),
  requireResourceScope("tarea", "id"),
  ctrl.veredicto,
);
router.get(
  "/cronograma-imprimible",
  requirePermission("cronograma.imprimir"),
  ctrl.cronogramaImprimible,
);

export default router;
