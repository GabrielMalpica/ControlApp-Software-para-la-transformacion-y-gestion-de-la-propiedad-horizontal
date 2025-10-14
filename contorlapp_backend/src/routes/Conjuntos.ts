// src/routes/conjuntos.ts
import { Router } from "express";
import { ConjuntoController } from "../controller/ConjuntoController";

const router = Router();
const controller = new ConjuntoController();

// Asignaciones
router.post("/:nit/operarios", controller.asignarOperario);
router.put("/:nit/administrador", controller.asignarAdministrador);
router.delete("/:nit/administrador", controller.eliminarAdministrador);

// Maquinaria
router.post("/:nit/maquinaria", controller.agregarMaquinaria);
router.post("/:nit/maquinaria/entregar", controller.entregarMaquinaria);

// Ubicaciones
router.post("/:nit/ubicaciones", controller.agregarUbicacion);
router.get("/:nit/ubicaciones/buscar", controller.buscarUbicacion);

// Cronograma / Tareas
router.post("/:nit/cronograma/tareas", controller.agregarTareaACronograma);
router.get("/:nit/tareas/por-fecha", controller.tareasPorFecha);
router.get("/:nit/tareas/por-operario/:operarioId", controller.tareasPorOperario);
router.get("/:nit/tareas/por-ubicacion", controller.tareasPorUbicacion);

export default router;
