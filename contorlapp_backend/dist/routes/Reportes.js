"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/reportes.ts
const express_1 = require("express");
const ReporteController_1 = require("../controller/ReporteController");
const router = (0, express_1.Router)();
const c = new ReporteController_1.ReporteController();
// DASHBOARD
router.get("/kpis", c.kpis);
router.get("/serie-diaria", c.serieDiariaPorEstado);
router.get("/por-conjunto", c.resumenPorConjunto);
router.get("/por-operario", c.resumenPorOperario);
router.get("/duracion-promedio", c.duracionPromedioPorEstado);
router.get("/mensual-detalle", c.reporteMensualDetalle);
router.get("/zonificacion/preventivas", c.zonificacionPreventivas);
router.get("/maquinaria/top", c.usoMaquinariaTop);
router.get("/herramientas/top", c.usoHerramientaTop);
router.get("/tipos", c.conteoPorTipo);
// LO QUE YA TENÍAS
router.get("/tareas/aprobadas", c.tareasAprobadasPorFecha);
router.get("/tareas/rechazadas", c.tareasRechazadasPorFecha);
router.get("/insumos/uso", c.usoDeInsumosPorFecha);
router.get("/tareas/estado", c.tareasPorEstado);
router.get("/tareas/detalle", c.tareasConDetalle);
exports.default = router;
