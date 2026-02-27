import { Router } from "express";
import { AuthController } from "../controller/AuthController";
import { authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new AuthController();

router.post("/login", controller.login);
router.post("/recuperar-contrasena", controller.recuperarContrasena);
router.get("/me", authRequired, controller.me);
router.post("/cambiar-contrasena", authRequired, controller.cambiarContrasena);

export default router;
