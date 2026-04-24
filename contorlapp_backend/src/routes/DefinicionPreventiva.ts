// src/routes/DefinicionPreventiva.ts
import { Router } from "express";
import {
  DefinicionTareaPreventivaController,
  asyncHandler,
} from "../controller/DefinicionTareaPreventivaController";

const router = Router();
const ctrl = new DefinicionTareaPreventivaController();

// 🔹 Definiciones (todas con /conjuntos/:nit/...)
router.post("/conjuntos/:nit/preventivas", asyncHandler(ctrl.crear));

router.get("/conjuntos/:nit/preventivas", asyncHandler(ctrl.listar));

router.patch("/conjuntos/:nit/preventivas/:id", asyncHandler(ctrl.actualizar));

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

router.post(
  "/conjuntos/:nit/preventivas/borrador/tarea",
  asyncHandler(ctrl.crearBloqueBorrador),
);

router.patch(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id",
  asyncHandler(ctrl.editarBloqueBorrador),
);
router.get(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id/opciones-reprogramacion",
  asyncHandler(ctrl.listarOpcionesReprogramacionBorrador),
);

router.get(
  "/conjuntos/:nit/preventivas/borrador/excluidas",
  asyncHandler(ctrl.listarExcluidasBorrador),
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
