"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/DefinicionPreventiva.ts
const express_1 = require("express");
const DefinicionTareaPreventivaController_1 = require("../controller/DefinicionTareaPreventivaController");
const router = (0, express_1.Router)();
const ctrl = new DefinicionTareaPreventivaController_1.DefinicionTareaPreventivaController();
// 🔹 Definiciones (todas con /conjuntos/:nit/...)
router.post("/conjuntos/:nit/preventivas", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.crear));
router.get("/conjuntos/:nit/preventivas", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listar));
router.patch("/conjuntos/:nit/preventivas/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.actualizar));
router.delete("/conjuntos/:nit/preventivas/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.eliminar));
// 🔹 Borrador
router.post("/conjuntos/:nit/preventivas/generar-cronograma", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.generarCronogramaMensual));
router.get("/conjuntos/:nit/preventivas/borrador", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarBorrador));
router.post("/conjuntos/:nit/preventivas/borrador/tarea", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.crearBloqueBorrador));
router.patch("/conjuntos/:nit/preventivas/borrador/tarea/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.editarBloqueBorrador));
router.get("/conjuntos/:nit/preventivas/borrador/tarea/:id/opciones-reprogramacion", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarOpcionesReprogramacionBorrador));
router.delete("/conjuntos/:nit/preventivas/borrador/tarea/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.eliminarBloqueBorrador));
// 🔹 Publicar
router.post("/conjuntos/:nit/preventivas/publicar", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.publicarCronograma));
router.get("/conjuntos/:nit/preventivas/maquinaria-disponible", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarMaquinariaDisponible));
exports.default = router;
