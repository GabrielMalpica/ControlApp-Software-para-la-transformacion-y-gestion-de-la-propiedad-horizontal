import { Router } from "express";
import { PrismaClient } from "../generated/prisma";
import { DefinicionTareaPreventivaController, asyncHandler } from "../controller/DefinicionTareaPreventivaController";

const router = Router();
const prisma = new PrismaClient();
const ctrl = new DefinicionTareaPreventivaController(prisma);

// Definiciones
router.post("/:nit/preventivas",            asyncHandler(ctrl.crear));
router.get("/:nit/preventivas",             asyncHandler(ctrl.listar));
router.patch("/:nit/preventivas/:id",       asyncHandler(ctrl.actualizar));
router.delete("/:nit/preventivas/:id",      asyncHandler(ctrl.eliminar));

// Borrador
router.post("/:nit/preventivas/generar-cronograma", asyncHandler(ctrl.generarCronogramaMensual));
router.get("/:nit/preventivas/borrador",            asyncHandler(ctrl.listarBorrador));
router.post("/:nit/preventivas/borrador/tarea",     asyncHandler(ctrl.crearBloqueBorrador));
router.patch("/:nit/preventivas/borrador/tarea/:id",asyncHandler(ctrl.editarBloqueBorrador));
router.delete("/:nit/preventivas/borrador/tarea/:id",asyncHandler(ctrl.eliminarBloqueBorrador));

// Publicar
router.post("/:nit/preventivas/publicar",   asyncHandler(ctrl.publicarCronograma));

export default router;
