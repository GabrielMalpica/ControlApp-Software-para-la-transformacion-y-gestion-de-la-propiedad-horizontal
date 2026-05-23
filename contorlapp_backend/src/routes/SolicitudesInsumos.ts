// src/routes/solicitudesInsumos.ts
import { Router } from "express";
import { SolicitudInsumoController } from "../controller/SolicitudInsumoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const controller = new SolicitudInsumoController();

router.use(authRequired);

router.post("/", requirePermission("solicitudes.ver"), controller.crear);
router.get("/", requirePermission("solicitudes.ver"), controller.listar);
router.get("/:id", requirePermission("solicitudes.ver"), controller.obtener);
router.post("/:id/aprobar", requirePermission("solicitudes.ver"), controller.aprobar);
router.delete("/:id", requirePermission("solicitudes.ver"), controller.eliminar);

export default router;
