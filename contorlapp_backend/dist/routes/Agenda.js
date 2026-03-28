"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/agenda.ts
const express_1 = require("express");
const AgendaMaquinariaController_1 = require("../controller/AgendaMaquinariaController");
const AgendaHerramientaController_1 = require("../controller/AgendaHerramientaController");
const router = (0, express_1.Router)();
const ctrl = new AgendaMaquinariaController_1.AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController_1.AgendaHerramientaController();
router.get("/empresa/:empresaNit/maquinaria", ctrl.agendaGlobal);
router.get("/empresa/:empresaNit/herramientas", ctrlHerr.agendaGlobal);
exports.default = router;
