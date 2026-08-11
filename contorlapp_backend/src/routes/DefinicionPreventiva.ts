// src/routes/DefinicionPreventiva.ts
import { Router } from "express";
import {
  DefinicionTareaPreventivaController,
  asyncHandler,
} from "../controller/DefinicionTareaPreventivaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireConjuntoScope } from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new DefinicionTareaPreventivaController();

router.use(authRequired);
router.use(requireRoles("gerente"));
router.use("/conjuntos/:nit", requireConjuntoScope("nit"));
router.use("/conjuntos/:nit", requirePermission("cronograma.publicar"));

// 🔹 Definiciones (todas con /conjuntos/:nit/...)
router.post("/conjuntos/:nit/preventivas", asyncHandler(ctrl.crear));

router.get("/conjuntos/:nit/preventivas", asyncHandler(ctrl.listar));

router.patch("/conjuntos/:nit/preventivas/:id", asyncHandler(ctrl.actualizar));

// ⚠️ Las rutas con segmento literal van SIEMPRE antes que `/:id`, o Express
// las captura como si `borrador` fuese un id.
router.delete("/conjuntos/:nit/preventivas", asyncHandler(ctrl.eliminarVarias));

router.delete(
  "/conjuntos/:nit/preventivas/borrador",
  asyncHandler(ctrl.descartarBorrador),
);

router.delete("/conjuntos/:nit/preventivas/:id", asyncHandler(ctrl.eliminar));

// 🔹 Borrador
router.post(
  "/conjuntos/:nit/preventivas/generar-cronograma",
  asyncHandler(ctrl.generarCronogramaMensual),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador",
  asyncHandler(ctrl.listarBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/estado",
  asyncHandler(ctrl.estadoBorrador),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/tarea",
  asyncHandler(ctrl.crearBloqueBorrador),
);

router.patch(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id",
  asyncHandler(ctrl.editarBloqueBorrador),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/tareas/reordenar-dia",
  asyncHandler(ctrl.reordenarTareasDiaBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id/opciones-reprogramacion",
  asyncHandler(ctrl.listarOpcionesReprogramacionBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/excluidas",
  asyncHandler(ctrl.listarExcluidasBorrador),
);

router.delete(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id",
  asyncHandler(ctrl.descartarExcluidaBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/huecos",
  asyncHandler(ctrl.sugerirHuecosExcluida),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/agendar",
  asyncHandler(ctrl.agendarExcluidaBorrador),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id/reemplazar-por-excluida",
  asyncHandler(ctrl.reemplazarConExcluida),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id/reasignar-operario",
  asyncHandler(ctrl.reasignarOperarioBorrador),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/reasignar-operario",
  asyncHandler(ctrl.reasignarOperarioExcluidaBorrador),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/dividir-manual",
  asyncHandler(ctrl.dividirExcluidaManual),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/bloques/:bloqueId/huecos",
  asyncHandler(ctrl.sugerirHuecosBloqueExcluida),
);

router.post(
  "/conjuntos/:nit/preventivas/borrador/excluidas/:id/bloques/:bloqueId/agendar",
  asyncHandler(ctrl.agendarBloqueExcluida),
);

router.delete(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id",
  asyncHandler(ctrl.eliminarBloqueBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/informe-actividad",
  asyncHandler(ctrl.informeActividadBorrador),
);

// 🔹 Publicar
router.post(
  "/conjuntos/:nit/preventivas/publicar",
  asyncHandler(ctrl.publicarCronograma),
);

router.get(
  "/conjuntos/:nit/preventivas/maquinaria-disponible",
  asyncHandler(ctrl.listarMaquinariaDisponible),
);

export default router;
