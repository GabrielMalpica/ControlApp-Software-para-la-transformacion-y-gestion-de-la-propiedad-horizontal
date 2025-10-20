import { Router } from "express";
import { PrismaClient } from "../generated/prisma";
import {
  DefinicionTareaPreventivaController,
  asyncHandler,
} from "../controller/DefinicionTareaPreventivaController";

const router = Router();
const prisma = new PrismaClient();
const controller = new DefinicionTareaPreventivaController(prisma);

// Crear definición preventiva
router.post("/:nit/preventivas", asyncHandler(controller.crear));

// Listar definiciones del conjunto
router.get("/:nit/preventivas", asyncHandler(controller.listar));

// Actualizar una definición
router.patch("/:nit/preventivas/:id", asyncHandler(controller.actualizar));

// Eliminar una definición
router.delete("/:nit/preventivas/:id", asyncHandler(controller.eliminar));

// Generar cronograma mensual (borrador) a partir de definiciones activas
router.post(
  "/:nit/preventivas/generar-cronograma",
  asyncHandler(controller.generarCronogramaMensual)
);

export default router;