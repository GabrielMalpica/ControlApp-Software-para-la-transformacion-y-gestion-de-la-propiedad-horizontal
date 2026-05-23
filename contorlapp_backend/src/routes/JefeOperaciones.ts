// src/routes/jefeOperaciones.routes.ts
import { Router } from "express";
import multer from "multer";
import { JefeOperacionesController } from "../controller/JefeOperacionesController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const controller = new JefeOperacionesController();

router.use(authRequired);
router.use(requireRoles("jefe_operaciones"));

// Multer temp folder
const upload = multer({ dest: "tmp/" });

// ✅ Endpoints
router.get("/tareas/pendientes", requirePermission("tareas.ver"), controller.listarPendientes);

// JSON veredicto
router.post("/tareas/:id/veredicto", requirePermission("tareas.veredicto"), controller.veredicto);

// Multipart veredicto + evidencias
router.post(
  "/tareas/:id/veredicto-multipart",
  requirePermission("tareas.veredicto"),
  upload.array("files", 10), // input name="files"
  controller.veredictoMultipart,
);

export default router;
