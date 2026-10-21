import { Router } from "express";
import { EvidenciaController } from "../controller/EvidenciaController";
import { authRequired } from "../middlewares/auth.middleware";

const router = Router();
const controller = new EvidenciaController();

router.use(authRequired);

// GET /evidencias/direccion?lat=&lng= -> calle, barrio y ciudad de un punto GPS
// para la marca de agua de las fotos. Va antes de "/:fileId" para no
// confundirse con un id de archivo.
router.get("/direccion", controller.direccion);

// GET /evidencias/:fileId -> streamea el binario de una evidencia desde Drive.
// El controller la sirve solo si el archivo es de una tarea, diagnóstico del
// Plan Esperanza o comprobante que el usuario puede ver (EvidenciaAccesoService);
// los documentos de la página web van por /commerce/web/archivos/:fileId.
router.get("/:fileId", controller.obtener);

export default router;
