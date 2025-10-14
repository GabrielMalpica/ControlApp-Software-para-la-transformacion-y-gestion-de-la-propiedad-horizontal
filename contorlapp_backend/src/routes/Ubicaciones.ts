// src/routes/ubicaciones.ts
import { Router } from "express";
import { UbicacionController } from "../controller/UbicacionController";

const router = Router();
const controller = new UbicacionController();

router.post("/ubicaciones/:ubicacionId/elementos", controller.agregarElemento);
router.get("/ubicaciones/:ubicacionId/elementos", controller.listarElementos);
router.get("/ubicaciones/:ubicacionId/elementos/buscar", controller.buscarElementoPorNombre);

export default router;
