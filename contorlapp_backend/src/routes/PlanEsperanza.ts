import { Router } from "express";

import { PlanEsperanzaController } from "../controller/PlanEsperanzaController";
import { uploadEvidencias } from "../middlewares/upload_evidencias";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new PlanEsperanzaController();

router.use(authRequired);

router.get("/conjuntos/:nit/config", requirePermission("plan_esperanza.acceso", "plan_esperanza.configurar"), requireConjuntoScope("nit"), ctrl.getConfig);
router.put("/conjuntos/:nit/config", requirePermission("plan_esperanza.configurar"), requireConjuntoScope("nit"), ctrl.updateConfig);

router.post("/conjuntos/:nit/iniciar", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.iniciarPlan);
router.get("/conjuntos/:nit/plan-activo", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.getPlanActivo);
router.get("/conjuntos/:nit/planes", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.listarPlanes);
router.get("/conjuntos/:nit/historico", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.obtenerHistorico);
router.post("/conjuntos/:nit/reiniciar", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.reiniciarPlan);
router.get("/conjuntos/:nit/verificar-zonas", requirePermission("plan_esperanza.acceso"), requireConjuntoScope("nit"), ctrl.verificarZonasNuevas);

router.put(
  "/diagnosticos/:id",
  requirePermission("plan_esperanza.acceso"),
  requireResourceScope("diagnostico", "id"),
  uploadEvidencias.single("foto"),
  ctrl.guardarDiagnostico
);

router.post("/planes/:id/finalizar", requirePermission("plan_esperanza.acceso"), requireResourceScope("plan", "id"), ctrl.finalizarPlan);
router.get("/planes/:id/informe", requirePermission("plan_esperanza.acceso"), requireResourceScope("plan", "id"), ctrl.obtenerInforme);

router.get(
  "/linea-tiempo/elemento/:elementoId",
  requirePermission("plan_esperanza.acceso"),
  requireResourceScope("elemento", "elementoId"),
  ctrl.obtenerLineaTiempoElemento
);

export default router;
