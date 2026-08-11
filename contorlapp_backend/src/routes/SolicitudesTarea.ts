// src/routes/solicitudes-tarea.ts
import { Router } from "express";
import { SolicitudTareaController } from "../controller/SolicitudTareaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudTareaController();

router.use(authRequired);
router.use(requireRoles("gerente", "jefe_operaciones"));

router.post(
  "/solicitudes-tarea/:solicitudId/aprobar",
  requirePermission("solicitudes.ver"),
  requireResourceScope("solicitudTarea", "solicitudId"),
  controller.aprobar,
);
router.post(
  "/solicitudes-tarea/:solicitudId/rechazar",
  requirePermission("solicitudes.ver"),
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
