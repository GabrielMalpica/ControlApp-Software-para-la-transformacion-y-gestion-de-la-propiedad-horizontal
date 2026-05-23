// src/routes/agenda.ts
import { Router } from "express";
import { AgendaMaquinariaController } from "../controller/AgendaMaquinariaController";
import { AgendaHerramientaController } from "../controller/AgendaHerramientaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";

const router = Router();
const ctrl = new AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController();

router.get(
  "/empresa/:empresaNit/maquinaria",
  authRequired,
  requirePermission("maquinaria.ver"),
  ctrl.agendaGlobal,
);
router.get(
  "/empresa/:empresaNit/herramientas",
  authRequired,
  requirePermission("herramientas.ver"),
  ctrlHerr.agendaGlobal,
);

export default router;
