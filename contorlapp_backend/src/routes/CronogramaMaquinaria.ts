// src/routes/CronogramaMaquinaria.ts
import { Router } from "express";

import { CronogramaMaquinariaController } from "../controller/CronogramaMaquinariaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const controller = new CronogramaMaquinariaController();

// Necesidades de maquinaria del mes en todos los conjuntos de la empresa.
router.get(
  "/empresas/:empresaNit/necesidades",
  authRequired,
  requirePermission("maquinaria.ver"),
  controller.listarNecesidades,
);

// Asignar una maquina real a una necesidad.
router.post(
  "/empresas/:empresaNit/asignaciones",
  authRequired,
  requirePermission("maquinaria.asignar"),
  controller.asignarMaquinaria,
);

router.delete(
  "/empresas/:empresaNit/asignaciones/:usoId",
  authRequired,
  requirePermission("maquinaria.asignar"),
  controller.liberarAsignacion,
);

export default router;
