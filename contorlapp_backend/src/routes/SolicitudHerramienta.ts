import { Router } from "express";
import { SolicitudHerramientaController } from "../controller/SolicitudHerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudHerramientaController();

router.use(authRequired);

router.post("/", requireRoles("gerente", "jefe_operaciones", "supervisor", "operario"), requirePermission("solicitudes.ver"), requireBodyConjuntoScope(), controller.crear);
router.get("/", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("solicitudes.ver"), controller.listar);
router.get("/:solicitudId", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("solicitudes.ver"), requireResourceScope("solicitudHerramienta", "solicitudId"), controller.obtener);
router.patch("/:solicitudId/estado", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireResourceScope("solicitudHerramienta", "solicitudId"), controller.cambiarEstado);

export default router;
