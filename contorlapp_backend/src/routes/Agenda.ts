// src/routes/agenda.ts
import { Router } from "express";
import { AgendaMaquinariaController } from "../controller/AgendaMaquinariaController";
import { AgendaHerramientaController } from "../controller/AgendaHerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import {
  requireConjuntoScope,
  requireEmpresaScope,
} from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController();

router.use(authRequired);
router.use("/empresa/:empresaNit", requireEmpresaScope("empresaNit"));
router.use("/conjunto/:conjuntoId", requireConjuntoScope("conjuntoId"));

router.get(
  "/empresa/:empresaNit/maquinaria",
  requirePermission("maquinaria.ver"),
  ctrl.agendaGlobal,
);
router.get(
  "/empresa/:empresaNit/herramientas",
  requirePermission("herramientas.ver"),
  ctrlHerr.agendaGlobal,
);

router.get(
  "/conjunto/:conjuntoId/maquinaria",
  requirePermission("maquinaria.ver"),
  ctrl.agendaConjunto,
);
router.get(
  "/conjunto/:conjuntoId/herramientas",
  requirePermission("herramientas.ver"),
  ctrlHerr.agendaConjunto,
);

export default router;
