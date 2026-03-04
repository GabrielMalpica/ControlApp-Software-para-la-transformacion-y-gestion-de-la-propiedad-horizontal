"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/agenda.ts
const express_1 = require("express");
const AgendaMaquinariaController_1 = require("../controller/AgendaMaquinariaController");
const router = (0, express_1.Router)();
const ctrl = new AgendaMaquinariaController_1.AgendaMaquinariaController();
router.get("/empresa/:empresaNit/maquinaria", ctrl.agendaGlobal);
exports.default = router;
