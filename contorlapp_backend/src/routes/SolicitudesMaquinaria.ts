// src/routes/solicitudesMaquinaria.ts
import { Router } from "express";
import { SolicitudMaquinariaController } from "../controller/SolicitudMaquinariaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const controller = new SolicitudMaquinariaController();

router.use(authRequired);

router.post("/", requirePermission("solicitudes.ver"), controller.crear);
router.get("/", requirePermission("solicitudes.ver"), controller.listar);
router.get("/:id", requirePermission("solicitudes.ver"), controller.obtener);
router.patch("/:id", requirePermission("solicitudes.ver"), controller.editar);
router.post("/:id/aprobar", requirePermission("solicitudes.ver"), controller.aprobar);
router.delete("/:id", requirePermission("solicitudes.ver"), controller.eliminar);

export default router;
