// src/routes/agenda.ts
import { Router } from "express";
import { AgendaMaquinariaController } from "../controller/AgendaMaquinariaController";
import { AgendaHerramientaController } from "../controller/AgendaHerramientaController";

const router = Router();
const ctrl = new AgendaMaquinariaController();
const ctrlHerr = new AgendaHerramientaController();

router.get("/empresa/:empresaNit/maquinaria", ctrl.agendaGlobal);
router.get("/empresa/:empresaNit/herramientas", ctrlHerr.agendaGlobal);

export default router;
