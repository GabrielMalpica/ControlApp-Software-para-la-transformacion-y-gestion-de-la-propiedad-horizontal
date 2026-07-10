import { Router } from "express";

import { PlanEsperanzaController } from "../controller/PlanEsperanzaController";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const ctrl = new PlanEsperanzaController();

router.get("/conjuntos/:nit/config", ctrl.getConfig);
router.put("/conjuntos/:nit/config", ctrl.updateConfig);

router.post("/conjuntos/:nit/iniciar", ctrl.iniciarPlan);
router.get("/conjuntos/:nit/plan-activo", ctrl.getPlanActivo);
router.get("/conjuntos/:nit/planes", ctrl.listarPlanes);
router.get("/conjuntos/:nit/historico", ctrl.obtenerHistorico);
router.post("/conjuntos/:nit/reiniciar", ctrl.reiniciarPlan);
router.get("/conjuntos/:nit/verificar-zonas", ctrl.verificarZonasNuevas);

router.put(
  "/diagnosticos/:id",
  uploadEvidencias.single("foto"),
  ctrl.guardarDiagnostico
);

router.post("/planes/:id/finalizar", ctrl.finalizarPlan);
router.get("/planes/:id/informe", ctrl.obtenerInforme);

router.get(
  "/linea-tiempo/elemento/:elementoId",
  ctrl.obtenerLineaTiempoElemento
);

export default router;
