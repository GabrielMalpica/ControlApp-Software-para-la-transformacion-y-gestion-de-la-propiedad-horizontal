// src/routes/CronogramaHerramienta.ts
import { Router } from "express";

import { CronogramaHerramientaController } from "../controller/CronogramaHerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireEmpresaScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new CronogramaHerramientaController();

router.use(authRequired);
router.use("/empresas/:empresaNit", requireEmpresaScope("empresaNit"));

// Necesidades de herramientas del mes en todos los conjuntos de la empresa.
router.get(
  "/empresas/:empresaNit/necesidades",
  requirePermission("herramientas.ver", "herramientas.asignar"),
  controller.listarNecesidades,
);

// Asignar herramienta (del conjunto y, si falta, en préstamo de la empresa) a una necesidad.
router.post(
  "/empresas/:empresaNit/asignaciones",
  requirePermission("herramientas.asignar"),
  controller.asignarHerramienta,
);

router.delete(
  "/empresas/:empresaNit/asignaciones/:usoId",
  requirePermission("herramientas.asignar"),
  requireResourceScope("usoHerramienta", "usoId"),
  controller.liberarAsignacion,
);

export default router;
