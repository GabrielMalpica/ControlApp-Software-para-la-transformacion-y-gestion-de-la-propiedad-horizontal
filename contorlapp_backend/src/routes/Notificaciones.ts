import { Router } from "express";
import { authRequired } from "../middlewares/auth.middleware";
import { NotificacionController } from "../controller/NotificacionController";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const controller = new NotificacionController();

router.use(authRequired);

router.get(
  "/cumpleanos/mes-actual",
  requirePermission("cumpleanos.ver"),
  controller.cumpleanosMesActual,
);
router.get(
  "/cumpleanos/anio",
  requirePermission("cumpleanos.ver"),
  controller.cumpleanosAnio,
);
router.get(
  "/cumpleanos/hoy",
  requirePermission("cumpleanos.ver"),
  controller.cumpleanosHoy,
);
router.get("/", controller.listar);
router.get("/no-leidas/count", controller.contarNoLeidas);
router.patch("/leidas", controller.marcarTodasLeidas);
router.patch("/:id/leida", controller.marcarLeida);

export default router;
