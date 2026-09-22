import { Router } from "express";
import { TareaController } from "../controller/TareaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireBodyConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const controller = new TareaController();

router.use(authRequired);

// CRUD
router.post("/", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireBodyConjuntoScope(), controller.crearTarea);
router.get("/", requirePermission("tareas.ver"), controller.listarTareas);
router.get("/:id", requirePermission("tareas.ver"), requireResourceScope("tarea", "id"), controller.obtenerTarea);
router.patch("/:id", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireResourceScope("tarea", "id"), controller.editarTarea);
router.delete("/:id", requirePermission("tareas.crear"), requireResourceScope("tarea", "id"), controller.eliminarTarea);

// Corregir cierre (evidencias/insumos de una tarea ya cerrada)
router.post(
  "/:id/corregir-cierre",
  requirePermission("tareas.editar_cierre"),
  requireResourceScope("tarea", "id"),
  ...uploadEvidencias.array("files", 10),
  controller.corregirCierre,
);

export default router;
