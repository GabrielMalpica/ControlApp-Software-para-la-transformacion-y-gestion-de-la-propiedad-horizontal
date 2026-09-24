import { Router } from "express";
import { CommerceController } from "../controller/CommerceController";
import { CommerceLifecycleController } from "../controller/CommerceLifecycleController";
import { CommerceOrderController } from "../controller/CommerceOrderController";
import { CommercePointsController } from "../controller/CommercePointsController";
import { CommerceWebhookController } from "../controller/CommerceWebhookController";
import { authOptional, authRequired } from "../middlewares/auth.middleware";
import { requirePermission, requirePermissionUnlessRoles } from "../middlewares/permission.middleware";
import { distributedRateLimit } from "../middlewares/rate-limit.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { uploadComprobante } from "../middlewares/upload_evidencias";

const router = Router();
const controller = new CommerceController();
const orderController = new CommerceOrderController();
const lifecycleController = new CommerceLifecycleController();
const pointsController = new CommercePointsController();
const webhookController = new CommerceWebhookController();
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

// Sin authRequired: WooCommerce se autentica con su propia firma HMAC
// (verificada dentro del controller), no con un Bearer de ControlApp. Ver
// isPublicRequest() en auth.middleware.ts, que exime justo esta ruta del
// guard generico.
router.post("/webhooks/woocommerce", webhookController.ordenActualizada);

router.get("/catalogo", authOptional, controller.listarCatalogo);
router.get("/catalogo/:productId", authOptional, controller.obtenerProducto);
router.get(
  "/catalogo/:productId/disponibilidad",
  authOptional,
  controller.obtenerDisponibilidadServicio,
);
// Estas 5 rutas las comparte un residente gestionando SU PROPIO pedido (sin
// permiso: ver [[assertPedidoAccess]] ya lo limita a lo suyo) y el personal
// operativo gestionando pedidos de conjunto (si necesita el permiso
// "comercio.pedidos.*", editable en Permisos). requirePermissionUnlessRoles
// deja pasar a residente directo y exige el permiso a cualquier otro rol.
router.get(
  "/pedidos/:pedidoId",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.ver"),
  lifecycleController.obtenerPedido,
);
router.post(
  "/pedidos/:pedidoId/estado",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.gestionar"),
  lifecycleController.cambiarEstado,
);
router.get(
  "/pedidos/:pedidoId/recepcion-preview",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  requirePermission("comercio.pedidos.gestionar"),
  lifecycleController.vistaPreviaRecepcion,
);
router.post(
  "/pedidos/:pedidoId/items/:itemId/mapeo",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  requirePermission("comercio.pedidos.gestionar"),
  lifecycleController.mapearItem,
);
router.post(
  "/pedidos/:pedidoId/comprobante",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.gestionar"),
  strictMutationLimit,
  ...uploadComprobante.single("comprobante"),
  lifecycleController.subirComprobante,
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
  requirePermission("comercio.pedidos.ver"),
  orderController.listarPedidosConjunto,
);
router.get(
  "/conjunto/pedidos/:pedidoId",
  authRequired,
  requireRoles("administrador", "gerente", "jefe_operaciones"),
  requirePermission("comercio.pedidos.ver"),
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
