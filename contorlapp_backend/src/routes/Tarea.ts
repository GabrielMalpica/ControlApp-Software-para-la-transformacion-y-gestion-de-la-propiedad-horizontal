// src/routes/tareas.ts (ejemplo)
import { Router } from "express";
import { TareaController } from "../controller/TareaController";

const r = Router();
const c = new TareaController();

r.post("/:tareaId/evidencias", c.agregarEvidencia);
r.post("/:tareaId/iniciar", c.iniciarTarea);
r.post("/:tareaId/no-completada", c.marcarNoCompletada);
r.post("/:tareaId/completar", c.completarConInsumos);
r.post("/:tareaId/aprobar", c.aprobarTarea);
r.post("/:tareaId/rechazar", c.rechazarTarea);
r.get("/:tareaId/resumen", c.resumen);

export default r;
