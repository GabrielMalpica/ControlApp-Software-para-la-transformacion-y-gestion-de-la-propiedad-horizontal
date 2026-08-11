import { Router } from "express";
import { CommerceController } from "../controller/CommerceController";
import { CommerceLifecycleController } from "../controller/CommerceLifecycleController";
import { CommerceOrderController } from "../controller/CommerceOrderController";
import { CommercePointsController } from "../controller/CommercePointsController";
import { authOptional, authRequired } from "../middlewares/auth.middleware";
import { distributedRateLimit } from "../middlewares/rate-limit.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const controller = new CommerceController();
const orderController = new CommerceOrderController();
const lifecycleController = new CommerceLifecycleController();
const pointsController = new CommercePointsController();
const strictMutationLimit = distributedRateLimit({
  name: "commerce:mutaciones",
  windowMs: 15 * 60 * 1000,
  limit: 20,
  key: (req) => req.user?.sub ?? req.ip ?? "sin-ip",
  message: "Has realizado demasiadas operaciones. Intenta mas tarde",
});
const orderCreationLimit = distributedRateLimit({
  name: "commerce:pedidos",
  windowMs: 10 * 60 * 1000,
  limit: 12,
  key: (req) => req.user?.sub ?? req.ip ?? "sin-ip",
  message: "Has intentado crear demasiados pedidos. Intenta mas tarde",
});

router.get("/catalogo", authOptional, controller.listarCatalogo);
router.get("/catalogo/:productId", authOptional, controller.obtenerProducto);
router.get(
  "/catalogo/:productId/disponibilidad",
  authOptional,
  controller.obtenerDisponibilidadServicio,
);
router.get(
  "/pedidos/:pedidoId",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  lifecycleController.obtenerPedido,
);
router.post(
  "/pedidos/:pedidoId/estado",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  lifecycleController.cambiarEstado,
);
router.get(
  "/pedidos/:pedidoId/recepcion-preview",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  lifecycleController.vistaPreviaRecepcion,
);
router.post(
  "/pedidos/:pedidoId/items/:itemId/mapeo",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  lifecycleController.mapearItem,
);
router.get(
  "/puntos/resumen",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  pointsController.obtenerResumen,
);
router.get(
  "/puntos/configuracion",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  pointsController.obtenerConfiguracion,
);
router.put(
  "/puntos/configuracion",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  pointsController.configurar,
);
router.post(
  "/puntos/redenciones",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  strictMutationLimit,
  pointsController.redimir,
);
router.post(
  "/puntos/ajustes",
  authRequired,
  requireRoles("gerente", "jefe_operaciones"),
  strictMutationLimit,
  pointsController.ajustar,
);
router.get(
  "/conjunto/pedidos",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  orderController.listarPedidosConjunto,
);
router.get(
  "/conjunto/pedidos/:pedidoId",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  orderController.obtenerPedidoConjunto,
);
router.post(
  "/conjunto/pedidos",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  orderCreationLimit,
  orderController.crearPedidoConjunto,
);
router.get(
  "/residente/pedidos",
  authRequired,
  requireRoles("residente"),
  orderController.listarPedidosResidente,
);
router.get(
  "/residente/pedidos/:pedidoId",
  authRequired,
  requireRoles("residente"),
  orderController.obtenerPedidoResidente,
);
router.post(
  "/residente/pedidos",
  authRequired,
  requireRoles("residente"),
  orderCreationLimit,
  orderController.crearPedidoResidente,
);

export default router;
