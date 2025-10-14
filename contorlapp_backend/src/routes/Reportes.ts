// src/routes/reportes.ts
import { Router } from "express";
import { ReporteController } from "../controller/ReporteController";

const router = Router();
const controller = new ReporteController();

// Tareas por fecha
router.get("/reportes/tareas/aprobadas", controller.tareasAprobadasPorFecha);
router.get("/reportes/tareas/rechazadas", controller.tareasRechazadasPorFecha);

// Insumos
router.get("/reportes/insumos/uso", controller.usoDeInsumosPorFecha);

// Tareas por estado y con detalle
router.get("/reportes/tareas/estado", controller.tareasPorEstado);
router.get("/reportes/tareas/detalle", controller.tareasConDetalle);

export default router;
