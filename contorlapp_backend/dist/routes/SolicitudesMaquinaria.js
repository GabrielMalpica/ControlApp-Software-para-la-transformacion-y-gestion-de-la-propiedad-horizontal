"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudesMaquinaria.ts
const express_1 = require("express");
const SolicitudMaquinariaController_1 = require("../controller/SolicitudMaquinariaController");
const router = (0, express_1.Router)();
const controller = new SolicitudMaquinariaController_1.SolicitudMaquinariaController();
router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:id", controller.obtener);
router.patch("/:id", controller.editar);
router.post("/:id/aprobar", controller.aprobar);
router.delete("/:id", controller.eliminar);
exports.default = router;
