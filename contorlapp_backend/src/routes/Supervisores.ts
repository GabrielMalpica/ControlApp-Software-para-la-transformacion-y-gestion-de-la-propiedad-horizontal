import { Router } from "express";
import { SupervisorController } from "../controller/SupervisorController";
import { requireRoles } from "../middlewares/role.middleware";
import { authRequired } from "../middlewares/auth.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const ctrl = new SupervisorController();

router.use(authRequired, requireRoles("supervisor"));
router.get("/tareas", ctrl.listarTareas);
router.post(
  "/tareas/:id/cerrar",
  uploadEvidencias.array("files", 10),
  ctrl.cerrarTarea
);
router.post("/tareas/:id/veredicto", ctrl.veredicto);
router.get("/cronograma-imprimible", ctrl.cronogramaImprimible);

export default router;
