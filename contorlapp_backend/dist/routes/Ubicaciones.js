"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/ubicaciones.ts
const express_1 = require("express");
const UbicacionController_1 = require("../controller/UbicacionController");
const router = (0, express_1.Router)();
const controller = new UbicacionController_1.UbicacionController();
router.post("/ubicaciones/:ubicacionId/elementos", controller.agregarElemento);
router.get("/ubicaciones/:ubicacionId/elementos", controller.listarElementos);
router.get("/ubicaciones/:ubicacionId/elementos/buscar", controller.buscarElementoPorNombre);
exports.default = router;
