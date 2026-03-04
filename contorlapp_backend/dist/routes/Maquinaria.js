"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/maquinarias.ts
const express_1 = require("express");
const MaquinariaController_1 = require("../controller/MaquinariaController");
const router = (0, express_1.Router)();
const controller = new MaquinariaController_1.MaquinariaController();
// Asignación y devolución
router.post("/:maquinariaId/asignar", controller.asignarAConjunto);
router.post("/:maquinariaId/devolver", controller.devolver);
// Consultas rápidas
router.get("/:maquinariaId/disponible", controller.estaDisponible);
router.get("/:maquinariaId/responsable", controller.obtenerResponsable);
router.get("/:maquinariaId/resumen", controller.resumenEstado);
router.get("/:maquinariaId/agenda/:conjuntoId", controller.agendaMaquinaria);
exports.default = router;
