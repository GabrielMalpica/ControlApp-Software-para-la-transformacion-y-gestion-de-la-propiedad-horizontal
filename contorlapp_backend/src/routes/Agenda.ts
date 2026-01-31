// src/routes/agenda.ts
import { Router } from "express";
import { AgendaMaquinariaController } from "../controller/AgendaMaquinariaController";

const router = Router();
const ctrl = new AgendaMaquinariaController();

router.get("/empresa/:empresaNit/maquinaria", ctrl.agendaGlobal);

export default router;
