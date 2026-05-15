"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/DefinicionPreventiva.ts
const express_1 = require("express");
const DefinicionTareaPreventivaController_1 = require("../controller/DefinicionTareaPreventivaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const router = (0, express_1.Router)();
const ctrl = new DefinicionTareaPreventivaController_1.DefinicionTareaPreventivaController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("gerente"));
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
router.post("/conjuntos/:nit/preventivas/borrador/tareas/reordenar-dia", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.reordenarTareasDiaBorrador));
router.get("/conjuntos/:nit/preventivas/borrador/tarea/:id/opciones-reprogramacion", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarOpcionesReprogramacionBorrador));
router.get("/conjuntos/:nit/preventivas/borrador/excluidas", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarExcluidasBorrador));
router.delete("/conjuntos/:nit/preventivas/borrador/excluidas/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.descartarExcluidaBorrador));
router.get("/conjuntos/:nit/preventivas/borrador/excluidas/:id/huecos", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.sugerirHuecosExcluida));
router.post("/conjuntos/:nit/preventivas/borrador/excluidas/:id/agendar", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.agendarExcluidaBorrador));
router.post("/conjuntos/:nit/preventivas/borrador/tarea/:id/reemplazar-por-excluida", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.reemplazarConExcluida));
router.post("/conjuntos/:nit/preventivas/borrador/tarea/:id/reasignar-operario", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.reasignarOperarioBorrador));
router.post("/conjuntos/:nit/preventivas/borrador/excluidas/:id/reasignar-operario", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.reasignarOperarioExcluidaBorrador));
router.post("/conjuntos/:nit/preventivas/borrador/excluidas/:id/dividir-manual", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.dividirExcluidaManual));
router.get("/conjuntos/:nit/preventivas/borrador/excluidas/:id/bloques/:bloqueId/huecos", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.sugerirHuecosBloqueExcluida));
router.post("/conjuntos/:nit/preventivas/borrador/excluidas/:id/bloques/:bloqueId/agendar", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.agendarBloqueExcluida));
router.delete("/conjuntos/:nit/preventivas/borrador/tarea/:id", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.eliminarBloqueBorrador));
router.get("/conjuntos/:nit/preventivas/borrador/informe-actividad", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.informeActividadBorrador));
// 🔹 Publicar
router.post("/conjuntos/:nit/preventivas/publicar", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.publicarCronograma));
router.get("/conjuntos/:nit/preventivas/maquinaria-disponible", (0, DefinicionTareaPreventivaController_1.asyncHandler)(ctrl.listarMaquinariaDisponible));
exports.default = router;
