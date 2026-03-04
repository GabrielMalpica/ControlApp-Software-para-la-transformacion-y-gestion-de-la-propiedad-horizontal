"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/solicitudesInsumos.ts
const express_1 = require("express");
const SolicitudInsumoController_1 = require("../controller/SolicitudInsumoController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const router = (0, express_1.Router)();
const controller = new SolicitudInsumoController_1.SolicitudInsumoController();
router.use(auth_middleware_1.authRequired);
router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:id", controller.obtener);
router.post("/:id/aprobar", controller.aprobar);
router.delete("/:id", controller.eliminar);
exports.default = router;
