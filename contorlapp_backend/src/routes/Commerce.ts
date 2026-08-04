import { Router } from "express";
import { CommerceController } from "../controller/CommerceController";
import { CommerceOrderController } from "../controller/CommerceOrderController";
import { authOptional, authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new CommerceController();
const orderController = new CommerceOrderController();

router.get("/catalogo", authOptional, controller.listarCatalogo);
router.get("/catalogo/:productId", authOptional, controller.obtenerProducto);
router.get("/residente/pedidos", authRequired, orderController.listarPedidosResidente);
router.get(
  "/residente/pedidos/:pedidoId",
  authRequired,
  orderController.obtenerPedidoResidente,
);
router.post("/residente/pedidos", authRequired, orderController.crearPedidoResidente);

export default router;
