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

router.delete(
  "/conjuntos/:nit/preventivas/borrador/tarea/:id",
  asyncHandler(ctrl.eliminarBloqueBorrador),
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
