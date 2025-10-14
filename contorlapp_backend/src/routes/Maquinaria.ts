// src/routes/maquinarias.ts
import { Router } from "express";
import { MaquinariaController } from "../controller/MaquinariaController";

const router = Router();
const controller = new MaquinariaController();

// Asignación y devolución
router.post("/maquinarias/:maquinariaId/asignar", controller.asignarAConjunto);
router.post("/maquinarias/:maquinariaId/devolver", controller.devolver);

// Consultas rápidas
router.get("/maquinarias/:maquinariaId/disponible", controller.estaDisponible);
router.get("/maquinarias/:maquinariaId/responsable", controller.obtenerResponsable);
router.get("/maquinarias/:maquinariaId/resumen", controller.resumenEstado);

export default router;
