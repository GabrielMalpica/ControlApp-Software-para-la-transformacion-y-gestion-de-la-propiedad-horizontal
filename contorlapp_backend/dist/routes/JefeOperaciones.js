"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/jefeOperaciones.routes.ts
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const JefeOperacionesController_1 = require("../controller/JefeOperacionesController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const permission_middleware_1 = require("../middlewares/permission.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const router = (0, express_1.Router)();
const controller = new JefeOperacionesController_1.JefeOperacionesController();
router.use(auth_middleware_1.authRequired);
router.use((0, role_middleware_1.requireRoles)("jefe_operaciones"));
// Multer temp folder
const upload = (0, multer_1.default)({ dest: "tmp/" });
// ✅ Endpoints
router.get("/tareas/pendientes", (0, permission_middleware_1.requirePermission)("tareas.ver"), controller.listarPendientes);
// JSON veredicto
router.post("/tareas/:id/veredicto", (0, permission_middleware_1.requirePermission)("tareas.veredicto"), controller.veredicto);
// Multipart veredicto + evidencias
router.post("/tareas/:id/veredicto-multipart", (0, permission_middleware_1.requirePermission)("tareas.veredicto"), upload.array("files", 10), // input name="files"
controller.veredictoMultipart);
exports.default = router;
