// src/routes/solicitudesInsumos.ts
import { Router } from "express";
import { SolicitudInsumoController } from "../controller/SolicitudInsumoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new SolicitudInsumoController();

router.use(authRequired);

router.post("/", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("solicitudes.ver"), requireBodyConjuntoScope(), controller.crear);
router.get("/", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("solicitudes.ver"), controller.listar);
router.get("/:id", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("solicitudes.ver"), requireResourceScope("solicitudInsumo", "id"), controller.obtener);
router.post("/:id/aprobar", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireResourceScope("solicitudInsumo", "id"), controller.aprobar);
router.delete("/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireResourceScope("solicitudInsumo", "id"), controller.eliminar);

export default router;
