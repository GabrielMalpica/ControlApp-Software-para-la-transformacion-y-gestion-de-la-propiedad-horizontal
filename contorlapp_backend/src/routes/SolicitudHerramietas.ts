import { Router } from "express";
import { SolicitudHerramientaController } from "../controller/SolicitudHerramientaController";

const router = Router();
const controller = new SolicitudHerramientaController();

router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:solicitudId", controller.obtener);
//router.patch("/:solicitudId/estado", controller.cambiarEstado);

export default router;
