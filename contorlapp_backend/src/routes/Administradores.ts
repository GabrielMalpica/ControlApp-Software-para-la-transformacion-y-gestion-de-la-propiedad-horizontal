// src/routes/administradores.ts
import { Router } from "express";
import { AdministradorController } from "../controller/AdministradorController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import {
  requireBodyConjuntoScope,
  requireConjuntoScope,
  requireResourceScope,
  requireSelfScope,
} from "../middlewares/tenant.middleware";

const router = Router();
const controller = new AdministradorController();

router.use(authRequired);
router.use(requireRoles("administrador"));
router.use("/:adminId", requireSelfScope("adminId"));

// Conjuntos del administrador
router.get("/:adminId/conjuntos", requirePermission("compromisos.ver"), controller.verConjuntos);
router.get("/:adminId/conjuntos/:conjuntoId/compromisos", requirePermission("compromisos.ver"), requireConjuntoScope("conjuntoId"), controller.listarCompromisosConjunto);
router.post("/:adminId/conjuntos/:conjuntoId/compromisos", requirePermission("compromisos.gestionar"), requireConjuntoScope("conjuntoId"), controller.crearCompromisoConjunto);
router.patch("/:adminId/compromisos/:id", requirePermission("compromisos.gestionar"), requireResourceScope("compromiso", "id"), controller.actualizarCompromiso);
router.delete("/:adminId/compromisos/:id", requirePermission("compromisos.gestionar"), requireResourceScope("compromiso", "id"), controller.eliminarCompromiso);

// Solicitudes
router.post("/:adminId/solicitudes/tarea", requirePermission("solicitudes.ver"), requireBodyConjuntoScope(), controller.solicitarTarea);
router.post("/:adminId/solicitudes/insumos", requirePermission("solicitudes.ver"), requireBodyConjuntoScope(), controller.solicitarInsumos);
router.post("/:adminId/solicitudes/maquinaria", requirePermission("solicitudes.ver"), requireBodyConjuntoScope(), controller.solicitarMaquinaria);

export default router;
