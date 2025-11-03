// src/routes/cronograma.ts
import { Router } from "express";
import { CronogramaController } from "../controller/CronogramaController";

const router = Router();
const controller = new CronogramaController();

// Consultas de tareas
router.get("/conjuntos/:nit/cronograma/tareas/por-operario/:operarioId", controller.tareasPorOperario);
router.get("/conjuntos/:nit/cronograma/tareas/por-fecha", controller.tareasPorFecha);
router.get("/conjuntos/:nit/cronograma/tareas/en-rango", controller.tareasEnRango);
router.get("/conjuntos/:nit/cronograma/tareas/por-ubicacion", controller.tareasPorUbicacion);

// Filtro avanzado (body JSON)
router.post("/conjuntos/:nit/cronograma/tareas/filtrar", controller.tareasPorFiltro);

// Export para calendarios (FullCalendar, etc.)
router.get("/conjuntos/:nit/cronograma/eventos", controller.exportarComoEventosCalendario);


router.get("/:nit/cronograma", controller.cronogramaMensual);

router.get("/:nit/operarios/sugerir", controller.sugerirOperarios);


export default router;
