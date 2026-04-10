// src/routes/administradores.ts
import { Router } from "express";
import { AdministradorController } from "../controller/AdministradorController";

const router = Router();
const controller = new AdministradorController();

// Conjuntos del administrador
router.get("/:adminId/conjuntos", controller.verConjuntos);
router.get("/:adminId/conjuntos/:conjuntoId/compromisos", controller.listarCompromisosConjunto);
router.post("/:adminId/conjuntos/:conjuntoId/compromisos", controller.crearCompromisoConjunto);
router.patch("/:adminId/compromisos/:id", controller.actualizarCompromiso);
router.delete("/:adminId/compromisos/:id", controller.eliminarCompromiso);

// Solicitudes
router.post("/:adminId/solicitudes/tarea", controller.solicitarTarea);
router.post("/:adminId/solicitudes/insumos", controller.solicitarInsumos);
router.post("/:adminId/solicitudes/maquinaria", controller.solicitarMaquinaria);

export default router;
