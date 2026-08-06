import { Router } from "express";
import { rateLimit } from "express-rate-limit";
import { CommerceController } from "../controller/CommerceController";
import { CommerceLifecycleController } from "../controller/CommerceLifecycleController";
import { CommerceOrderController } from "../controller/CommerceOrderController";
import { CommercePointsController } from "../controller/CommercePointsController";
import { authOptional, authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new CommerceController();
const orderController = new CommerceOrderController();
const lifecycleController = new CommerceLifecycleController();
const pointsController = new CommercePointsController();
const strictMutationLimit = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: { ok: false, message: "Has realizado demasiadas operaciones. Intenta mas tarde" },
});
const orderCreationLimit = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 12,
  standardHeaders: "draft-7",
  legacyHeaders: false,
  message: { ok: false, message: "Has intentado crear demasiados pedidos. Intenta mas tarde" },
});

router.get("/catalogo", authOptional, controller.listarCatalogo);
router.get("/catalogo/:productId", authOptional, controller.obtenerProducto);
router.get(
  "/catalogo/:productId/disponibilidad",
  authOptional,
  controller.obtenerDisponibilidadServicio,
);
router.get("/pedidos/:pedidoId", authRequired, lifecycleController.obtenerPedido);
router.post(
  "/pedidos/:pedidoId/estado",
  authRequired,
  lifecycleController.cambiarEstado,
);
router.get(
  "/pedidos/:pedidoId/recepcion-preview",
  authRequired,
  lifecycleController.vistaPreviaRecepcion,
);
router.post(
  "/pedidos/:pedidoId/items/:itemId/mapeo",
  authRequired,
  lifecycleController.mapearItem,
);
router.get("/puntos/resumen", authRequired, pointsController.obtenerResumen);
router.get(
  "/puntos/configuracion",
  authRequired,
  pointsController.obtenerConfiguracion,
);
router.put("/puntos/configuracion", authRequired, pointsController.configurar);
router.post(
  "/puntos/redenciones",
  authRequired,
  strictMutationLimit,
  pointsController.redimir,
);
router.post("/puntos/ajustes", authRequired, strictMutationLimit, pointsController.ajustar);
router.get("/conjunto/pedidos", authRequired, orderController.listarPedidosConjunto);
router.get(
  "/conjunto/pedidos/:pedidoId",
  authRequired,
  orderController.obtenerPedidoConjunto,
);
router.post(
  "/conjunto/pedidos",
  authRequired,
  orderCreationLimit,
  orderController.crearPedidoConjunto,
);
router.get("/residente/pedidos", authRequired, orderController.listarPedidosResidente);
router.get(
  "/residente/pedidos/:pedidoId",
  authRequired,
  orderController.obtenerPedidoResidente,
);
router.post(
  "/residente/pedidos",
  authRequired,
  orderCreationLimit,
  orderController.crearPedidoResidente,
);

export default router;
