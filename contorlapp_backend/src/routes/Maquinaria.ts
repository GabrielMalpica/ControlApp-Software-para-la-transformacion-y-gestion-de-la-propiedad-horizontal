// src/routes/maquinarias.ts
import { Router } from "express";
import { MaquinariaController } from "../controller/MaquinariaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new MaquinariaController();

router.use(authRequired);

// Asignación y devolución
router.post("/:maquinariaId/asignar", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireResourceScope("maquinaria", "maquinariaId"), controller.asignarAConjunto);
router.post("/:maquinariaId/devolver", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireResourceScope("maquinaria", "maquinariaId"), controller.devolver);

// Consultas rápidas
router.get("/:maquinariaId/disponible", requirePermission("maquinaria.ver"), requireResourceScope("maquinaria", "maquinariaId"), controller.estaDisponible);
router.get("/:maquinariaId/responsable", requirePermission("maquinaria.ver"), requireResourceScope("maquinaria", "maquinariaId"), controller.obtenerResponsable);
router.get("/:maquinariaId/resumen", requirePermission("maquinaria.ver"), requireResourceScope("maquinaria", "maquinariaId"), controller.resumenEstado);
router.get("/:maquinariaId/agenda/:conjuntoId", requirePermission("maquinaria.ver"), requireResourceScope("maquinaria", "maquinariaId"), requireConjuntoScope("conjuntoId"), controller.agendaMaquinaria);

export default router;
