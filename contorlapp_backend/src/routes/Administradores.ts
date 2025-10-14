// src/routes/administradores.ts
import { Router } from "express";
import { AdministradorController } from "../controller/AdministradorController";

const router = Router();
const controller = new AdministradorController();

// Conjuntos del administrador
router.get("/:adminId/conjuntos", controller.verConjuntos);

// Solicitudes
router.post("/:adminId/solicitudes/tarea", controller.solicitarTarea);
router.post("/:adminId/solicitudes/insumos", controller.solicitarInsumos);
router.post("/:adminId/solicitudes/maquinaria", controller.solicitarMaquinaria);

export default router;
