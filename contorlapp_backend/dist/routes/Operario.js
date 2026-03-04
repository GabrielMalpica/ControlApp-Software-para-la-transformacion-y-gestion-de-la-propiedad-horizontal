"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/operarios.ts
const express_1 = require("express");
const OperarioController_1 = require("../controller/OperarioController");
const upload_evidencias_1 = require("../middlewares/upload_evidencias");
const router = (0, express_1.Router)();
const controller = new OperarioController_1.OperarioController();
// Tareas del operario
router.post("/operarios/:operarioId/tareas/asignar", controller.asignarTarea);
router.post("/operarios/:operarioId/tareas/:tareaId/iniciar", controller.iniciarTarea);
router.post("/operarios/:operarioId/tareas/completar", controller.marcarComoCompletada);
router.post("/operarios/:operarioId/tareas/:tareaId/cerrar", upload_evidencias_1.uploadEvidencias.array("files", 10), controller.cerrarTareaConEvidencias);
router.post("/operarios/:operarioId/tareas/:tareaId/no-completada", controller.marcarComoNoCompletada);
router.get("/operarios/:operarioId/tareas/dia", controller.tareasDelDia);
router.get("/operarios/:operarioId/tareas", controller.listarTareas);
// Horas
router.get("/operarios/:operarioId/horas/restantes", controller.horasRestantesEnSemana);
router.get("/operarios/:operarioId/horas/resumen", controller.resumenDeHoras);
exports.default = router;
