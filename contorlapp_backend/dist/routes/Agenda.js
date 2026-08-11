"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/agenda.ts
const express_1 = require("express");
const AgendaMaquinariaController_1 = require("../controller/AgendaMaquinariaController");
const AgendaHerramientaController_1 = require("../controller/AgendaHerramientaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const tenant_middleware_1 = require("../middlewares/tenant.middleware");
const router = (0, express_1.Router)();
const ctrl = new AgendaMaquinariaController_1.AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController_1.AgendaHerramientaController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"));
router.use("/empresa/:empresaNit", (0, tenant_middleware_1.requireEmpresaScope)("empresaNit"));
router.get("/empresa/:empresaNit/maquinaria", (0, permission_middleware_1.requirePermission)("maquinaria.ver"), ctrl.agendaGlobal);
router.get("/empresa/:empresaNit/herramientas", (0, permission_middleware_1.requirePermission)("herramientas.ver"), ctrlHerr.agendaGlobal);
exports.default = router;
