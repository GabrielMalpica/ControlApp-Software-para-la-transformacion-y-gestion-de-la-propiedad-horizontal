import { Router } from "express";
import { HerramientaController } from "../controller/HerramientaController";

const router = Router();
const controller = new HerramientaController();

router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:herramientaId", controller.obtener);
router.patch("/:herramientaId", controller.editar);
router.delete("/:herramientaId", controller.eliminar);

export default router;
