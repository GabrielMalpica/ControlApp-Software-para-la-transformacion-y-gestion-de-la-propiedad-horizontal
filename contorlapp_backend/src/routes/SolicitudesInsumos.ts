// src/routes/solicitudesInsumos.ts
import { Router } from "express";
import { SolicitudInsumoController } from "../controller/SolicitudInsumoController";

const router = Router();
const controller = new SolicitudInsumoController();

router.post("/", controller.crear);
router.get("/", controller.listar);
router.get("/:id", controller.obtener);
router.post("/:id/aprobar", controller.aprobar);
router.delete("/:id", controller.eliminar);

export default router;
