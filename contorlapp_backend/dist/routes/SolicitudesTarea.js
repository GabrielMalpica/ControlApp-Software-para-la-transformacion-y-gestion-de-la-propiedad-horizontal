"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudes-tarea.ts
const express_1 = require("express");
const SolicitudTareaController_1 = require("../controller/SolicitudTareaController");
const router = (0, express_1.Router)();
const controller = new SolicitudTareaController_1.SolicitudTareaController();
router.post("/solicitudes-tarea/:solicitudId/aprobar", controller.aprobar);
router.post("/solicitudes-tarea/:solicitudId/rechazar", controller.rechazar);
router.get("/solicitudes-tarea/:solicitudId/estado", controller.estadoActual);
exports.default = router;
