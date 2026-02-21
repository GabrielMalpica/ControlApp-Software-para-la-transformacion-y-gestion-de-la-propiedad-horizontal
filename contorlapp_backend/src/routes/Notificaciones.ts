import { Router } from "express";
import { authRequired } from "../middlewares/auth.middleware";
import { NotificacionController } from "../controller/NotificacionController";

const router = Router();
const controller = new NotificacionController();

router.use(authRequired);

router.get("/", controller.listar);
router.get("/no-leidas/count", controller.contarNoLeidas);
router.patch("/leidas", controller.marcarTodasLeidas);
router.patch("/:id/leida", controller.marcarLeida);

export default router;
