import { Router } from "express";
import { TareaController } from "../controller/TareaController";

const router = Router();
const controller = new TareaController();

// CRUD
router.post("/", controller.crearTarea);
router.get("/", controller.listarTareas);
router.get("/:id", controller.obtenerTarea);
router.patch("/:id", controller.editarTarea);
router.delete("/:id", controller.eliminarTarea);

export default router;