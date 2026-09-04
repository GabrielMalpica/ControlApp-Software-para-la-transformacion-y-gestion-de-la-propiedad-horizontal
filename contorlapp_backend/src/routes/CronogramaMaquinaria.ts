// src/routes/CronogramaMaquinaria.ts
import { Router } from "express";

import { CronogramaMaquinariaController } from "../controller/CronogramaMaquinariaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireEmpresaScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new CronogramaMaquinariaController();

router.use(authRequired);
router.use("/empresas/:empresaNit", requireEmpresaScope("empresaNit"));

// Necesidades de maquinaria del mes en todos los conjuntos de la empresa.
router.get(
  "/empresas/:empresaNit/necesidades",
  requirePermission("maquinaria.ver", "maquinaria.asignar"),
  controller.listarNecesidades,
);

// Asignar una maquina real a una necesidad.
router.post(
  "/empresas/:empresaNit/asignaciones",
  requirePermission("maquinaria.asignar"),
  controller.asignarMaquinaria,
);

router.delete(
  "/empresas/:empresaNit/asignaciones/:usoId",
  requirePermission("maquinaria.asignar"),
  requireResourceScope("usoMaquinaria", "usoId"),
  controller.liberarAsignacion,
);

export default router;
