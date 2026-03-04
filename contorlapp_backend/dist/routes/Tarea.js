"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const TareaController_1 = require("../controller/TareaController");
const router = (0, express_1.Router)();
const controller = new TareaController_1.TareaController();
// CRUD
router.post("/", controller.crearTarea);
router.get("/", controller.listarTareas);
router.get("/:id", controller.obtenerTarea);
router.patch("/:id", controller.editarTarea);
router.delete("/:id", controller.eliminarTarea);
exports.default = router;
