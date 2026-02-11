// src/routes/reportes.ts
import { Router } from "express";
import { ReporteController } from "../controller/ReporteController";

const router = Router();
const c = new ReporteController();

// DASHBOARD
router.get("/kpis", c.kpis);
router.get("/serie-diaria", c.serieDiariaPorEstado);
router.get("/por-conjunto", c.resumenPorConjunto);
router.get("/por-operario", c.resumenPorOperario);
router.get("/duracion-promedio", c.duracionPromedioPorEstado);
router.get("/mensual-detalle", c.reporteMensualDetalle);
router.get("/maquinaria/top", c.usoMaquinariaTop);
router.get("/herramientas/top", c.usoHerramientaTop);
router.get("/tipos", c.conteoPorTipo);

// LO QUE YA TENÍAS
router.get("/tareas/aprobadas", c.tareasAprobadasPorFecha);
router.get("/tareas/rechazadas", c.tareasRechazadasPorFecha);
router.get("/insumos/uso", c.usoDeInsumosPorFecha);
router.get("/tareas/estado", c.tareasPorEstado);
router.get("/tareas/detalle", c.tareasConDetalle);

export default router;