import { Router } from "express";

import { AsistenciaController } from "../controller/AsistenciaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import {
  requireBodyConjuntoScope,
  requireConjuntoScope,
  requireResourceScope,
} from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new AsistenciaController();

router.use(authRequired);

// Catalogo de conceptos
router.get("/conceptos", requirePermission("asistencia.ver"), ctrl.listarConceptos);
router.put(
  "/conceptos/:id",
  requirePermission("asistencia.registrar_manual"),
  requireResourceScope("conceptoAsistencia", "id"),
  ctrl.actualizarConcepto,
);

// QR por conjunto
router.get(
  "/conjuntos/:nit/qr",
  requirePermission("asistencia.qr.gestionar"),
  requireConjuntoScope("nit"),
  ctrl.obtenerQr,
);
router.post(
  "/conjuntos/:nit/qr/regenerar",
  requirePermission("asistencia.qr.gestionar"),
  requireConjuntoScope("nit"),
  ctrl.regenerarQr,
);

// Check-in del operario
router.post(
  "/checkin",
  requirePermission("asistencia.marcar"),
  requireBodyConjuntoScope("conjuntoId"),
  ctrl.checkin,
);

// Grid y resumen mensual
router.get("/grid", requirePermission("asistencia.ver"), ctrl.getGrid);
router.get("/resumen", requirePermission("asistencia.ver"), ctrl.getResumen);
router.get("/visitas-supervisores", requirePermission("asistencia.ver"), ctrl.getVisitasSupervisores);
router.get("/exportar", requirePermission("asistencia.exportar"), ctrl.exportarExcel);

// Registro manual (falta, permiso, vacaciones, etc)
router.put("/registro", requirePermission("asistencia.registrar_manual"), ctrl.upsertRegistro);
router.post(
  "/registro/bulk",
  requirePermission("asistencia.registrar_manual"),
  ctrl.bulkUpsertRegistro,
);

// Turnos extra / reemplazos
router.get(
  "/turnos-extra",
  requirePermission("asistencia.ver", "asistencia.turnos_extra.gestionar"),
  ctrl.listarTurnosExtra,
);
router.post(
  "/turnos-extra",
  requirePermission("asistencia.turnos_extra.gestionar"),
  ctrl.crearTurnoExtra,
);
router.put(
  "/turnos-extra/:id",
  requirePermission("asistencia.turnos_extra.gestionar"),
  requireResourceScope("turnoExtra", "id"),
  ctrl.actualizarTurnoExtra,
);
router.delete(
  "/turnos-extra/:id",
  requirePermission("asistencia.turnos_extra.gestionar"),
  requireResourceScope("turnoExtra", "id"),
  ctrl.eliminarTurnoExtra,
);

export default router;
