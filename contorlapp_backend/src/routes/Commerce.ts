import { Router } from "express";
import { CommerceController } from "../controller/CommerceController";
import { CommerceLifecycleController } from "../controller/CommerceLifecycleController";
import { CommerceOrderController } from "../controller/CommerceOrderController";
import { CommercePointsController } from "../controller/CommercePointsController";
import { CommerceWebhookController } from "../controller/CommerceWebhookController";
import { FactusWebhookController } from "../controller/FactusWebhookController";
import { PagoAdminController } from "../controller/PagoAdminController";
import { PagoWooController } from "../controller/PagoWooController";
import { SaldoServicioController } from "../controller/SaldoServicioController";
import { WebRegistrosController } from "../controller/WebRegistrosController";
import { requirePagosWooHmac } from "../middlewares/pagos-woo-hmac.middleware";
import { authOptional, authRequired } from "../middlewares/auth.middleware";
import { requirePermission, requirePermissionUnlessRoles } from "../middlewares/permission.middleware";
import { distributedRateLimit } from "../middlewares/rate-limit.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { uploadArchivoWeb, uploadComprobante } from "../middlewares/upload_evidencias";
import { prevalidarWebArchivosHmac, requireWebArchivosHmac } from "../middlewares/web-archivos-hmac.middleware";

const router = Router();
const controller = new CommerceController();
const orderController = new CommerceOrderController();
const lifecycleController = new CommerceLifecycleController();
const pointsController = new CommercePointsController();
const webhookController = new CommerceWebhookController();
const factusWebhookController = new FactusWebhookController();
const pagoWooController = new PagoWooController();
const pagoAdminController = new PagoAdminController();
const saldoController = new SaldoServicioController();
const webRegistrosController = new WebRegistrosController();
// Todas las subidas de la pagina web llegan desde la IP del servidor de
// WordPress; por eso no pasan por el limite global de subidas (ver index.ts)
// y tienen uno propio, holgado para varios registros seguidos.
const webArchivosIpLimit = distributedRateLimit({
  name: "commerce:web-archivos",
  windowMs: 15 * 60 * 1000,
  limit: 150,
  key: (req) => req.ip ?? "sin-ip",
  message: "Demasiados archivos recibidos desde la pagina web. Intenta mas tarde",
});
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
// "Ya pague": ademas del limite general de mutaciones (strictMutationLimit),
// como mucho una consulta a Factus cada 5s por pedido -Factus tambien tiene
// su propio 429, esto es para no golpearlo sin necesidad-.
const pagoVerificarLimit = distributedRateLimit({
  name: "commerce:pago-verificar",
  windowMs: 5 * 1000,
  limit: 1,
  key: (req) => `${req.user?.sub ?? req.ip ?? "sin-ip"}:${req.params.pedidoId}`,
  message: "Espera unos segundos antes de volver a verificar el pago",
});
// Plugin controlapp-factus-pay: todo llega desde la IP del servidor de la
// tienda, asi que no pasa por el limite global por IP (ver index.ts). Tiene
// uno propio por IP, holgado, antes de la firma, y despues de la firma uno
// por orden (crear) y otro por cobro (verificar, igual que "Ya pague" de la app).
const pagosWooIpLimit = distributedRateLimit({
  name: "commerce:pagos-woo",
  windowMs: 15 * 60 * 1000,
  limit: 900,
  key: (req) => req.ip ?? "sin-ip",
  message: "Demasiadas solicitudes de pago desde la tienda. Intenta mas tarde",
});
const pagosWooCrearLimit = distributedRateLimit({
  name: "commerce:pagos-woo-crear",
  windowMs: 10 * 60 * 1000,
  limit: 10,
  key: (req) => `orden:${String(req.body?.wooOrderId ?? "sin-orden")}`,
  message: "Se pidieron demasiados codigos para este pedido. Intenta en unos minutos",
});
const pagosWooVerificarLimit = distributedRateLimit({
  name: "commerce:pagos-woo-verificar",
  windowMs: 5 * 1000,
  limit: 1,
  key: (req) => `ref:${req.params.referenceCode}`,
  message: "Espera unos segundos antes de volver a verificar el pago",
});
// "Verificar con Factus" desde el panel: una consulta cada 10 s por cobro.
const pagoAdminVerificarLimit = distributedRateLimit({
  name: "commerce:pago-admin-verificar",
  windowMs: 10 * 1000,
  limit: 1,
  key: (req) => `${req.user?.sub ?? req.ip ?? "sin-ip"}:${req.params.cobroId}`,
  message: "Espera unos segundos antes de volver a verificar este cobro",
});

// Sin authRequired: WooCommerce se autentica con su propia firma HMAC
// (verificada dentro del controller), no con un Bearer de ControlApp. Ver
// isPublicRequest() en auth.middleware.ts, que exime justo esta ruta del
// guard generico.
router.post("/webhooks/woocommerce", webhookController.ordenActualizada);

// Webhook de Factus Pay: sin JWT, la llave viaja en el query string y se
// valida en el servicio (ver FactusWebhookService e isPublicRequest).
router.post("/webhooks/factus-pay", factusWebhookController.recibir);

// Plugin controlapp-factus-pay de la tienda: sin JWT, firma HMAC (ver
// requirePagosWooHmac e isPublicRequest en auth.middleware.ts).
router.post("/pagos/woo/cobros", pagosWooIpLimit, requirePagosWooHmac, pagosWooCrearLimit, pagoWooController.crear);
router.get("/pagos/woo/cobros/:referenceCode", pagosWooIpLimit, requirePagosWooHmac, pagoWooController.obtener);
router.post(
  "/pagos/woo/cobros/:referenceCode/verificar",
  pagosWooIpLimit,
  requirePagosWooHmac,
  pagosWooVerificarLimit,
  pagoWooController.verificar,
);
// Saldo de servicios con anticipo y mora, desde la tienda (mismo HMAC).
const pagosWooSaldoLimit = distributedRateLimit({
  name: "commerce:pagos-woo-saldo",
  windowMs: 10 * 60 * 1000,
  limit: 10,
  key: (req) => `orden:${String(req.body?.wooOrderId ?? "sin-orden")}`,
  message: "Se pidieron demasiados codigos para este saldo. Intenta en unos minutos",
});
router.post("/pagos/woo/saldos/terminado", pagosWooIpLimit, requirePagosWooHmac, saldoController.servicioTerminado);
router.post("/pagos/woo/saldos/consultar", pagosWooIpLimit, requirePagosWooHmac, saldoController.consultarTienda);
router.post(
  "/pagos/woo/saldos/cobro",
  pagosWooIpLimit,
  requirePagosWooHmac,
  pagosWooSaldoLimit,
  saldoController.cobrarTienda,
);
router.post("/pagos/woo/mora/consulta", pagosWooIpLimit, requirePagosWooHmac, saldoController.moraTienda);

// Plugin puente de WordPress (controlapp-archivos-drive): documentos de los
// formularios de la pagina web hacia Drive. Sin JWT: firma HMAC que incluye el
// hash del archivo (ver web-archivos-hmac.middleware e isPublicRequest). La
// prevalidacion va antes de multer para no escribir en disco algo sin firma.
router.post(
  "/web/archivos",
  webArchivosIpLimit,
  prevalidarWebArchivosHmac,
  ...uploadArchivoWeb.single("archivo"),
  requireWebArchivosHmac,
  webRegistrosController.subirArchivo,
);
// Pantalla de solo lectura de ControlApp: postulaciones de trabajadores y
// conjuntos registrados en la web, con sus documentos en Drive.
const equipoWeb = [authRequired, requireRoles("gerente", "jefe_operaciones"), requirePermission("web.solicitudes.ver")];
router.get("/web/postulaciones", ...equipoWeb, webRegistrosController.listarPostulaciones);
router.get("/web/conjuntos", ...equipoWeb, webRegistrosController.listarConjuntos);
router.get("/web/archivos/:fileId", ...equipoWeb, webRegistrosController.obtenerArchivo);
// Marcar "ya la revisamos" o borrar una postulacion (aprobar/rechazar sigue en WordPress).
const gestionWeb = [authRequired, requireRoles("gerente", "jefe_operaciones"), requirePermission("web.solicitudes.gestionar")];
router.post("/web/postulaciones/:id/revision", ...gestionWeb, webRegistrosController.marcarRevision);
router.delete("/web/postulaciones/:id", ...gestionWeb, webRegistrosController.eliminarPostulacion);

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
// Cobro por Factus Pay (QR): reemplaza a comprobante+OCR como metodo por
// defecto. Mismos guards que /estado y /comprobante -residente gestiona lo
// suyo, el resto necesita el permiso de comercio.pedidos.gestionar-.
router.post(
  "/pedidos/:pedidoId/pago",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.gestionar"),
  strictMutationLimit,
  lifecycleController.crearPago,
);
router.get(
  "/pedidos/:pedidoId/pago",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.ver"),
  lifecycleController.obtenerPago,
);
router.post(
  "/pedidos/:pedidoId/pago/verificar",
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
  requirePermissionUnlessRoles(["residente"], "comercio.pedidos.gestionar"),
  strictMutationLimit,
  pagoVerificarLimit,
  lifecycleController.verificarPago,
);
// Panel de pagos (gerente / jefe de operaciones): historial, cobros que
// necesitan una decision, reporte de recaudo y conciliacion con Factus.
// Las rutas fijas van antes de "/pagos/:cobroId".
const equipoPagos = [authRequired, requireRoles("gerente", "jefe_operaciones")];
router.get("/pagos", ...equipoPagos, requirePermission("comercio.pedidos.ver"), pagoAdminController.listar);
router.get("/pagos/conteo", ...equipoPagos, requirePermission("comercio.pedidos.ver"), pagoAdminController.conteo);
router.get("/pagos/salud", ...equipoPagos, requirePermission("comercio.pedidos.ver"), pagoAdminController.salud);
router.get(
  "/pagos/reportes/recaudo",
  ...equipoPagos,
  requirePermission("comercio.pedidos.ver"),
  pagoAdminController.reporteRecaudo,
);
router.get(
  "/pagos/conciliacion",
  ...equipoPagos,
  requirePermission("comercio.pedidos.ver"),
  pagoAdminController.ultimaConciliacion,
);
router.post(
  "/pagos/conciliacion",
  ...equipoPagos,
  requirePermission("comercio.pedidos.gestionar"),
  strictMutationLimit,
  pagoAdminController.conciliar,
);
router.get("/pagos/:cobroId", ...equipoPagos, requirePermission("comercio.pedidos.ver"), pagoAdminController.obtener);
router.post(
  "/pagos/:cobroId/verificar",
  ...equipoPagos,
  requirePermission("comercio.pedidos.gestionar"),
  pagoAdminVerificarLimit,
  pagoAdminController.verificar,
);
router.post(
  "/pagos/:cobroId/resolver",
  ...equipoPagos,
  requirePermission("comercio.pedidos.gestionar"),
  strictMutationLimit,
  pagoAdminController.resolver,
);

// Saldos de servicios con anticipo: cada cliente ve y paga los SUYOS (el
// servicio filtra por su cuenta y su correo; uno ajeno responde 404).
const clientesSaldo = [
  authRequired,
  requireRoles("residente", "administrador", "gerente", "jefe_operaciones"),
];
const saldoVerificarLimit = distributedRateLimit({
  name: "commerce:saldo-verificar",
  windowMs: 5 * 1000,
  limit: 1,
  key: (req) => `${req.user?.sub ?? req.ip ?? "sin-ip"}:${req.params.saldoId}`,
  message: "Espera unos segundos antes de volver a verificar el pago",
});
router.get("/saldos", ...clientesSaldo, saldoController.listarMios);
router.get("/saldos/:saldoId", ...clientesSaldo, saldoController.obtenerMio);
router.post("/saldos/:saldoId/pago", ...clientesSaldo, strictMutationLimit, saldoController.pagarMio);
router.post(
  "/saldos/:saldoId/pago/verificar",
  ...clientesSaldo,
  strictMutationLimit,
  saldoVerificarLimit,
  saldoController.verificarMio,
);

// "Clientes en mora" (gerente / jefe de operaciones): datos de contacto del
// cliente, por eso un permiso propio.
router.get("/mora", ...equipoPagos, requirePermission("comercio.mora.ver"), saldoController.listarMora);
router.post(
  "/mora/:saldoId/resolver",
  ...equipoPagos,
  requirePermission("comercio.mora.gestionar"),
  strictMutationLimit,
  saldoController.resolver,
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
