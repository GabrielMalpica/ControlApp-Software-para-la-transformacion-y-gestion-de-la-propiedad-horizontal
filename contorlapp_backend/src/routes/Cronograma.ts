// src/routes/cronograma.ts
import { Router } from "express";
import { CronogramaController } from "../controller/CronogramaController";

const router = Router();
const controller = new CronogramaController();

// Sugerencia de operarios para un rango
router.get("/conjuntos/:nit/operarios/sugerir", controller.sugerirOperarios);

// Vistas de cronograma
router.get("/conjuntos/:nit/cronograma", controller.cronogramaMensual);       // lista cruda del mes
router.get("/conjuntos/:nit/cronograma/mes", controller.calendarioMensual);   // resumen por día (para el calendario)

// Consultas de tareas
router.get("/conjuntos/:nit/cronograma/tareas/por-operario/:operarioId", controller.tareasPorOperario);
router.get("/conjuntos/:nit/cronograma/tareas/por-fecha", controller.tareasPorFecha);
router.get("/conjuntos/:nit/cronograma/tareas/en-rango", controller.tareasEnRango);
router.get("/conjuntos/:nit/cronograma/tareas/por-ubicacion", controller.tareasPorUbicacion);

// Filtro avanzado (POST con body)
router.post("/conjuntos/:nit/cronograma/tareas/filtrar", controller.tareasPorFiltro);

// Export a formato de calendario (FullCalendar, etc.)
router.get("/conjuntos/:nit/cronograma/eventos", controller.exportarComoEventosCalendario);

export default router;
