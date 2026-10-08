// src/routes/RecursoAgenda.ts
//
// Agenda de recursos (maquinaria + herramientas). Reemplaza a
// /cronograma-maquinaria, /cronograma-herramienta y /agenda. Ver
// docs/agenda-recursos.md.
import { Router } from "express";

import { RecursoAgendaController } from "../controller/RecursoAgendaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireConjuntoScope, requireEmpresaScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new RecursoAgendaController();

const VER = ["maquinaria.ver", "maquinaria.asignar", "herramientas.ver", "herramientas.asignar"];
const ASIGNAR = ["maquinaria.asignar", "herramientas.asignar"];

router.use(authRequired);
router.use("/empresas/:empresaNit", requireEmpresaScope("empresaNit"));
router.use("/conjuntos/:nit", requireConjuntoScope("nit"));

// Lecturas
router.get("/empresas/:empresaNit/agenda", requirePermission(...VER), controller.agenda);
router.get("/empresas/:empresaNit/necesidades", requirePermission(...VER), controller.necesidades);
router.get("/empresas/:empresaNit/alertas", requirePermission(...VER), controller.alertas);
router.get(
  "/empresas/:empresaNit/necesidades/:necesidadId/candidatos",
  requirePermission(...ASIGNAR),
  controller.candidatos,
);
router.get(
  "/empresas/:empresaNit/unidades/:clase/:unidadId/historial",
  requirePermission(...VER),
  controller.historial,
);
router.get("/empresas/:empresaNit/configuracion", requirePermission(...VER), controller.obtenerConfiguracion);
router.get("/conjuntos/:nit/semana", requirePermission(...VER), controller.semanaConjunto);
router.get("/conjuntos/:nit/capacidad-borrador", requirePermission(...VER), controller.capacidadBorrador);

// Escrituras (el controlador exige además el permiso de la clase concreta)
router.post("/empresas/:empresaNit/reservas", requirePermission(...ASIGNAR), controller.reservar);
router.post(
  "/empresas/:empresaNit/reservas/:reservaId/cancelar",
  requirePermission(...ASIGNAR),
  controller.cancelar,
);
router.post(
  "/empresas/:empresaNit/reservas/:reservaId/reemplazar",
  requirePermission(...ASIGNAR),
  controller.reemplazar,
);
router.post("/empresas/:empresaNit/mantenimientos", requirePermission(...ASIGNAR), controller.mantenimiento);
router.patch(
  "/empresas/:empresaNit/configuracion",
  requireRoles("gerente", "jefe_operaciones"),
  controller.actualizarConfiguracion,
);

export default router;
