// src/routes/maquinarias.ts
import { Router } from "express";
import { MaquinariaController } from "../controller/MaquinariaController";

const router = Router();
const controller = new MaquinariaController();

// Asignación y devolución
router.post("/:maquinariaId/asignar", controller.asignarAConjunto);
router.post("/:maquinariaId/devolver", controller.devolver);

// Consultas rápidas
router.get("/:maquinariaId/disponible", controller.estaDisponible);
router.get("/:maquinariaId/responsable", controller.obtenerResponsable);
router.get("/:maquinariaId/resumen", controller.resumenEstado);

export default router;
