// src/routes/operarios.ts
import { Router } from "express";
import { OperarioController } from "../controller/OperarioController";

const router = Router();
const controller = new OperarioController();

// Tareas del operario
router.post("/operarios/:operarioId/tareas/asignar", controller.asignarTarea);
router.post("/operarios/:operarioId/tareas/:tareaId/iniciar", controller.iniciarTarea);
router.post("/operarios/:operarioId/tareas/completar", controller.marcarComoCompletada);
router.post("/operarios/:operarioId/tareas/:tareaId/no-completada", controller.marcarComoNoCompletada);

router.get("/operarios/:operarioId/tareas/dia", controller.tareasDelDia);
router.get("/operarios/:operarioId/tareas", controller.listarTareas);

// Horas
router.get("/operarios/:operarioId/horas/restantes", controller.horasRestantesEnSemana);
router.get("/operarios/:operarioId/horas/resumen", controller.resumenDeHoras);

export default router;
