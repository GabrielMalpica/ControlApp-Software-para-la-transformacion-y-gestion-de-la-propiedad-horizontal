import { Router } from "express";
import { EvidenciaController } from "../controller/EvidenciaController";
import { authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new EvidenciaController();

router.use(authRequired);

// GET /evidencias/:fileId -> streamea el binario de una evidencia desde Drive.
// Cualquier usuario autenticado puede pedirla: el scope "drive.file" de la
// cuenta de servicio ya limita el acceso solo a archivos que ella subió.
router.get("/:fileId", controller.obtener);

export default router;
