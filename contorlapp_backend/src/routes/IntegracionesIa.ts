// src/routes/IntegracionesIa.ts
//
// Panel de integraciones de IA (MCP). Exclusivo del rol gerente, validado
// aqui en el servidor: ningun otro rol, aunque tenga permisos amplios.
import { Router } from "express";

import { IntegracionesIaController } from "../controller/IntegracionesIaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requireRoles } from "../middlewares/role.middleware";

const router = Router();
const controller = new IntegracionesIaController();

router.use(authRequired, requireRoles("gerente"));

router.get("/configuracion", controller.configuracion);
router.get("/conexiones", controller.listar);
router.post("/conexiones/revocar-todas", controller.revocarTodas);
router.post("/conexiones/:id/revocar", controller.revocar);
router.put("/conexiones/:id/permisos", controller.reducirPermisos);
router.get("/conexiones/:id/actividad", controller.actividad);
router.get("/aprobaciones", controller.aprobaciones);
router.post("/aprobaciones/:id/decision", controller.decidir);

export default router;
