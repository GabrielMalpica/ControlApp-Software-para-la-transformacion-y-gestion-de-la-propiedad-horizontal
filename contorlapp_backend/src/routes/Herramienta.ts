import { Router } from "express";
import { HerramientaController } from "../controller/HerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new HerramientaController();

router.use(authRequired);

router.post("/", requirePermission("herramientas.gestionar"), controller.crear);
router.get("/", requirePermission("herramientas.ver", "herramientas.gestionar"), controller.listar);
router.get("/:herramientaId", requirePermission("herramientas.ver", "herramientas.gestionar"), requireResourceScope("herramienta", "herramientaId"), controller.obtener);
router.patch("/:herramientaId", requirePermission("herramientas.gestionar"), requireResourceScope("herramienta", "herramientaId"), controller.editar);
router.delete("/:herramientaId", requirePermission("herramientas.gestionar"), requireResourceScope("herramienta", "herramientaId"), controller.eliminar);

export default router;
