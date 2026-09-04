// src/routes/solicitudesInsumos.ts
import { Router } from "express";
import { SolicitudInsumoController } from "../controller/SolicitudInsumoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudInsumoController();

router.use(authRequired);

router.post("/", requirePermission("solicitudes.crear"), requireBodyConjuntoScope(), controller.crear);
router.get("/", requirePermission("solicitudes.ver"), controller.listar);
router.get("/:id", requirePermission("solicitudes.ver"), requireResourceScope("solicitudInsumo", "id"), controller.obtener);
router.post("/:id/aprobar", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudInsumo", "id"), controller.aprobar);
router.delete("/:id", requirePermission("solicitudes.gestionar"), requireResourceScope("solicitudInsumo", "id"), controller.eliminar);

export default router;
