"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/administradores.ts
const express_1 = require("express");
const AdministradorController_1 = require("../controller/AdministradorController");
const router = (0, express_1.Router)();
const controller = new AdministradorController_1.AdministradorController();
// Conjuntos del administrador
router.get("/:adminId/conjuntos", controller.verConjuntos);
// Solicitudes
router.post("/:adminId/solicitudes/tarea", controller.solicitarTarea);
router.post("/:adminId/solicitudes/insumos", controller.solicitarInsumos);
router.post("/:adminId/solicitudes/maquinaria", controller.solicitarMaquinaria);
exports.default = router;
