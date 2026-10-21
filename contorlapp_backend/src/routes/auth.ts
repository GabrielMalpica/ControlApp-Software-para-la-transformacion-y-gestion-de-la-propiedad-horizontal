import { Router } from "express";
import { AuthController } from "../controller/AuthController";
import { authOptional, authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new AuthController();

router.post("/login", controller.login);
// Responde 410: la recuperacion con correo + cedula quedo desactivada.
router.post("/recuperar-contrasena", controller.recuperarContrasena);
router.post("/refresh", controller.refresh);
router.post("/logout", authOptional, controller.logout);
router.post("/logout-todas", authRequired, controller.logoutTodas);
router.get("/me", authRequired, controller.me);
router.get("/perfil-resumen", authRequired, controller.perfilResumen);
router.post("/cambiar-contrasena", authRequired, controller.cambiarContrasena);
router.post(
  "/cambiar-contrasena-inicial",
  authRequired,
  controller.cambiarContrasenaInicial
);
router.post(
  "/usuarios/:userId/cambiar-contrasena",
  authRequired,
  requirePermission("usuarios.gestionar"),
  requireResourceScope("usuario", "userId"),
  controller.cambiarContrasenaUsuario
);

export default router;
