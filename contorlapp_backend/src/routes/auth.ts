import { Router } from "express";
import { AuthController } from "../controller/AuthController";
import { authRequired } from "../middlewares/auth.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new AuthController();

router.post("/login", controller.login);
router.post("/recuperar-contrasena", controller.recuperarContrasena);
router.post("/logout", authRequired, controller.logout);
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
  requireRoles("gerente"),
  requirePermission("usuarios.gestionar"),
  requireResourceScope("usuario", "userId"),
  controller.cambiarContrasenaUsuario
);

export default router;
