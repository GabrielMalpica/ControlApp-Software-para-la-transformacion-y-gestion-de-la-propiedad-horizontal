// src/routes/jefeOperaciones.routes.ts
import { Router } from "express";
import { JefeOperacionesController } from "../controller/JefeOperacionesController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";
import { uploadEvidencias } from "../middlewares/upload_evidencias";

const router = Router();
const controller = new JefeOperacionesController();

router.use(authRequired);

// El prefijo conserva el nombre historico del perfil, pero el acceso depende
// del permiso efectivo y del tenant, no de un rol fijo.
router.get("/tareas/pendientes", requirePermission("tareas.ver"), controller.listarPendientes);

// JSON veredicto
router.post("/tareas/:id/veredicto", requirePermission("tareas.veredicto"), requireResourceScope("tarea", "id"), controller.veredicto);

// Multipart veredicto + evidencias
router.post(
  "/tareas/:id/veredicto-multipart",
  requirePermission("tareas.veredicto"),
  requireResourceScope("tarea", "id"),
  uploadEvidencias.array("files", 10),
  controller.veredictoMultipart,
);

export default router;
