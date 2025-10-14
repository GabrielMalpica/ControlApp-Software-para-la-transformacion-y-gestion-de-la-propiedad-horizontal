// src/routes/tareas.ts
import { Router } from "express";
import { TareaController } from "../controller/TareaController";

const router = Router();
const controller = new TareaController();

router.post("/tareas/:tareaId/evidencias", controller.agregarEvidencia);
router.post("/tareas/:tareaId/iniciar", controller.iniciarTarea);
router.post("/tareas/:tareaId/no-completada", controller.marcarNoCompletada);
router.post("/tareas/:tareaId/aprobar", controller.aprobarTarea);
router.post("/tareas/:tareaId/rechazar", controller.rechazarTarea);
router.get("/tareas/:tareaId/resumen", controller.resumen);

export default router;
