// src/routes/jefeOperaciones.routes.ts
import { Router } from "express";
import multer from "multer";
import { JefeOperacionesController } from "../controller/JefeOperacionesController";

const router = Router();
const controller = new JefeOperacionesController();

// Multer temp folder
const upload = multer({ dest: "tmp/" });

// ✅ Endpoints
router.get("/tareas/pendientes", controller.listarPendientes);

// JSON veredicto
router.post("/tareas/:id/veredicto", controller.veredicto);

// Multipart veredicto + evidencias
router.post(
  "/tareas/:id/veredicto-multipart",
  upload.array("files", 10), // input name="files"
  controller.veredictoMultipart,
);

export default router;