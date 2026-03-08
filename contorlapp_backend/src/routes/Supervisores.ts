import { Router } from "express";
import { SupervisorController } from "../controller/SupervisorController";
import { authRequired } from "../middlewares/auth.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const ctrl = new SupervisorController();

router.use(authRequired);

router.get("/tareas", requireRoles("supervisor"), ctrl.listarTareas);
router.post(
  "/tareas/:id/cerrar",
  requireRoles("supervisor", "gerente", "jefe_operaciones"),
  uploadEvidencias.array("files", 10),
  ctrl.cerrarTarea,
);
router.post("/tareas/:id/veredicto", requireRoles("supervisor"), ctrl.veredicto);
router.get(
  "/cronograma-imprimible",
  requireRoles("supervisor"),
  ctrl.cronogramaImprimible,
);

export default router;
