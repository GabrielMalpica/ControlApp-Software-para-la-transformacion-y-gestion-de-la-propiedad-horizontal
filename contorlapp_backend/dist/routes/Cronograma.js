"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/cronograma.ts
const express_1 = require("express");
const CronogramaController_1 = require("../controller/CronogramaController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const router = (0, express_1.Router)();
const controller = new CronogramaController_1.CronogramaController();
// Sugerencia de operarios para un rango
router.get("/conjuntos/:nit/operarios/sugerir", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.sugerirOperarios);
// Vistas de cronograma
router.get("/conjuntos/:nit/cronograma", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.cronogramaMensual); // lista cruda del mes
router.get("/conjuntos/:nit/cronograma/informe-actividad", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.informeMensualActividad);
router.get("/conjuntos/:nit/cronograma/excluidas-standby", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.excluidas_ver"), controller.listarExcluidasStandby);
router.delete("/conjuntos/:nit/cronograma/publicado", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente"), (0, permission_middleware_1.requirePermission)("cronograma.eliminar_publicado"), controller.eliminarCronogramaPublicado);
router.get("/conjuntos/:nit/cronograma/mes", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.calendarioMensual); // resumen por día (para el calendario)
// Consultas de tareas
router.get("/conjuntos/:nit/cronograma/tareas/por-operario/:operarioId", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.tareasPorOperario);
router.get("/conjuntos/:nit/cronograma/tareas/por-fecha", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.tareasPorFecha);
router.get("/conjuntos/:nit/cronograma/tareas/en-rango", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.tareasEnRango);
router.get("/conjuntos/:nit/cronograma/tareas/por-ubicacion", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.tareasPorUbicacion);
// Filtro avanzado (POST con body)
router.post("/conjuntos/:nit/cronograma/tareas/filtrar", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.tareasPorFiltro);
// Export a formato de calendario (FullCalendar, etc.)
router.get("/conjuntos/:nit/cronograma/eventos", auth_middleware_1.authRequired, (0, permission_middleware_1.requirePermission)("cronograma.ver"), controller.exportarComoEventosCalendario);
exports.default = router;
