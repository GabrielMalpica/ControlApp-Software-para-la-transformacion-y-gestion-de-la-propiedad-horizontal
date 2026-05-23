// src/routes/solicitudes-tarea.ts
import { Router } from "express";
import { SolicitudTareaController } from "../controller/SolicitudTareaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const controller = new SolicitudTareaController();

router.use(authRequired);

router.post(
  "/solicitudes-tarea/:solicitudId/aprobar",
  requirePermission("solicitudes.ver"),
  controller.aprobar,
);
router.post(
  "/solicitudes-tarea/:solicitudId/rechazar",
  requirePermission("solicitudes.ver"),
  controller.rechazar,
);
router.get(
  "/solicitudes-tarea/:solicitudId/estado",
  requirePermission("solicitudes.ver"),
  controller.estadoActual,
);

export default router;
