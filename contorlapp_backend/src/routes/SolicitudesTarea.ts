// src/routes/solicitudes-tarea.ts
import { Router } from "express";
import { SolicitudTareaController } from "../controller/SolicitudTareaController";

const router = Router();
const controller = new SolicitudTareaController();

router.post("/solicitudes-tarea/:solicitudId/aprobar", controller.aprobar);
router.post("/solicitudes-tarea/:solicitudId/rechazar", controller.rechazar);
router.get("/solicitudes-tarea/:solicitudId/estado", controller.estadoActual);

export default router;
