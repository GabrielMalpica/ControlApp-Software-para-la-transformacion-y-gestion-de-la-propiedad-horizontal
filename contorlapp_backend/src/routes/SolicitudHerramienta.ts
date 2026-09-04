import { Router } from "express";
import { SolicitudHerramientaController } from "../controller/SolicitudHerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudHerramientaController();

router.use(authRequired);

router.post("/", requirePermission("solicitudes.crear"), requireBodyConjuntoScope(), controller.crear);
router.get("/", requirePermission("solicitudes.ver"), controller.listar);
router.get("/:solicitudId", requirePermission("solicitudes.ver"), requireResourceScope("solicitudHerramienta", "solicitudId"), controller.obtener);
router.patch("/:solicitudId/estado", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudHerramienta", "solicitudId"), controller.cambiarEstado);

export default router;
