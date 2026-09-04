// src/routes/solicitudes-tarea.ts
import { Router } from "express";
import { SolicitudTareaController } from "../controller/SolicitudTareaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudTareaController();

router.use(authRequired);

router.post(
  "/solicitudes-tarea/:solicitudId/aprobar",
  requirePermission("solicitudes.gestionar"),
  requireResourceScope("solicitudTarea", "solicitudId"),
  controller.aprobar,
);
router.post(
  "/solicitudes-tarea/:solicitudId/rechazar",
  requirePermission("solicitudes.gestionar"),
  requireResourceScope("solicitudTarea", "solicitudId"),
  controller.rechazar,
);
router.get(
  "/solicitudes-tarea/:solicitudId/estado",
  requirePermission("solicitudes.ver"),
  requireResourceScope("solicitudTarea", "solicitudId"),
  controller.estadoActual,
);

export default router;
