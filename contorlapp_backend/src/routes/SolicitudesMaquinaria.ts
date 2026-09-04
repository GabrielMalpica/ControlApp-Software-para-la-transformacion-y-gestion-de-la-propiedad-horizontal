// src/routes/solicitudesMaquinaria.ts
import { Router } from "express";
import { SolicitudMaquinariaController } from "../controller/SolicitudMaquinariaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudMaquinariaController();

router.use(authRequired);

router.post("/", requirePermission("solicitudes.crear"), requireBodyConjuntoScope(), controller.crear);
router.get("/", requirePermission("solicitudes.ver"), controller.listar);
router.get("/:id", requirePermission("solicitudes.ver"), requireResourceScope("solicitudMaquinaria", "id"), controller.obtener);
router.patch("/:id", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudMaquinaria", "id"), controller.editar);
router.post("/:id/aprobar", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudMaquinaria", "id"), controller.aprobar);
router.delete("/:id", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudMaquinaria", "id"), controller.eliminar);

export default router;
