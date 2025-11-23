import { Router } from "express";
import { PrismaClient } from "../generated/prisma";
import { InventarioController } from "../controller/InventarioController";

const prisma = new PrismaClient();
const controller = new InventarioController(prisma);
export const inventarioRouter = Router();

inventarioRouter.post("/inventarios/:inventarioId/insumos", controller.agregarInsumo);
inventarioRouter.get("/inventarios/:inventarioId/insumos", controller.listarInsumos);
inventarioRouter.get("/inventarios/:inventarioId/insumos-detalle", controller.listarInsumosDetallado);
inventarioRouter.get("/inventarios/:inventarioId/insumos/:insumoId", controller.buscarInsumoPorId);
inventarioRouter.delete("/inventarios/:inventarioId/insumos/:insumoId", controller.eliminarInsumo);
inventarioRouter.post("/inventarios/:inventarioId/insumos/:insumoId/consumir", controller.consumirInsumoPorId);
inventarioRouter.get("/inventarios/:inventarioId/insumos-bajos", controller.listarInsumosBajos);
inventarioRouter.get("/inventarios/:inventarioId/insumos-bajos/detalle", controller.listarInsumosBajosDetallado);

export default inventarioRouter;