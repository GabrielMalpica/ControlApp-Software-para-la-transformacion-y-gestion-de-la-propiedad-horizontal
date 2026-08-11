import { Router } from "express";
import { HerramientaController } from "../controller/HerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new HerramientaController();

router.use(authRequired);

router.post("/", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), controller.crear);
router.get("/", requirePermission("herramientas.ver"), controller.listar);
router.get("/:herramientaId", requirePermission("herramientas.ver"), requireResourceScope("herramienta", "herramientaId"), controller.obtener);
router.patch("/:herramientaId", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireResourceScope("herramienta", "herramientaId"), controller.editar);
router.delete("/:herramientaId", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.gestionar"), requireResourceScope("herramienta", "herramientaId"), controller.eliminar);

export default router;
