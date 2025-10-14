// src/routes/supervisores.ts
import { Router } from "express";
import { SupervisorController } from "../controller/SupervisorController";

const router = Router();
const controller = new SupervisorController();

router.post("/supervisores/:supervisorId/tareas/:tareaId/recibir", controller.recibirTareaFinalizada);
router.post("/supervisores/:supervisorId/tareas/:tareaId/aprobar", controller.aprobarTarea);
router.post("/supervisores/:supervisorId/tareas/:tareaId/rechazar", controller.rechazarTarea);
router.get("/supervisores/:supervisorId/tareas/pendientes", controller.listarTareasPendientes);

export default router;
