"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/agenda.ts
const express_1 = require("express");
const AgendaMaquinariaController_1 = require("../controller/AgendaMaquinariaController");
const AgendaHerramientaController_1 = require("../controller/AgendaHerramientaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const router = (0, express_1.Router)();
const ctrl = new AgendaMaquinariaController_1.AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController_1.AgendaHerramientaController();
router.get("/empresa/:empresaNit/maquinaria", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("maquinaria.ver"), ctrl.agendaGlobal);
router.get("/empresa/:empresaNit/herramientas", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("herramientas.ver"), ctrlHerr.agendaGlobal);
exports.default = router;
