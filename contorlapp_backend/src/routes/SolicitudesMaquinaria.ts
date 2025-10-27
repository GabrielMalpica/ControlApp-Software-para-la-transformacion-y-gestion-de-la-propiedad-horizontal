// src/routes/solicitudesMaquinaria.ts
import { Router } from "express";
import { SolicitudMaquinariaController } from "../controller/SolicitudMaquinariaController";

const router = Router();
const controller = new SolicitudMaquinariaController();

router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:id", controller.obtener);
router.patch("/:id", controller.editar);
router.post("/:id/aprobar", controller.aprobar);
router.delete("/:id", controller.eliminar);

export default router;
