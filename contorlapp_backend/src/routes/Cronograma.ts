// src/routes/cronograma.ts
import { Router } from "express";
import { CronogramaController } from "../controller/CronogramaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const controller = new CronogramaController();

// Sugerencia de operarios para un rango
router.get(
  "/conjuntos/:nit/operarios/sugerir",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.sugerirOperarios,
);

// Vistas de cronograma
router.get(
  "/conjuntos/:nit/cronograma",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.cronogramaMensual,
);       // lista cruda del mes
router.get(
  "/conjuntos/:nit/cronograma/informe-actividad",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.informeMensualActividad,
);
router.get(
  "/conjuntos/:nit/cronograma/excluidas-standby",
  authRequired,
  requirePermission("cronograma.excluidas_ver"),
  controller.listarExcluidasStandby,
);
router.delete(
  "/conjuntos/:nit/cronograma/publicado",
  authRequired,
  requireRoles("gerente"),
  requirePermission("cronograma.eliminar_publicado"),
  controller.eliminarCronogramaPublicado,
);
router.get(
  "/conjuntos/:nit/cronograma/mes",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.calendarioMensual,
);   // resumen por día (para el calendario)

// Consultas de tareas
router.get(
  "/conjuntos/:nit/cronograma/tareas/por-operario/:operarioId",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.tareasPorOperario,
);
router.get(
  "/conjuntos/:nit/cronograma/tareas/por-fecha",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.tareasPorFecha,
);
router.get(
  "/conjuntos/:nit/cronograma/tareas/en-rango",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.tareasEnRango,
);
router.get(
  "/conjuntos/:nit/cronograma/tareas/por-ubicacion",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.tareasPorUbicacion,
);

// Filtro avanzado (POST con body)
router.post(
  "/conjuntos/:nit/cronograma/tareas/filtrar",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.tareasPorFiltro,
);

// Export a formato de calendario (FullCalendar, etc.)
router.get(
  "/conjuntos/:nit/cronograma/eventos",
  authRequired,
  requirePermission("cronograma.ver"),
  controller.exportarComoEventosCalendario,
);

export default router;
