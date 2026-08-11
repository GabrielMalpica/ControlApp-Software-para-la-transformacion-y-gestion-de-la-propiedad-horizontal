// src/routes/ubicaciones.ts
import { Router } from "express";
import { UbicacionController } from "../controller/UbicacionController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new UbicacionController();

router.use(authRequired);

router.post("/ubicaciones/:ubicacionId/elementos", requireRoles("gerente", "jefe_operaciones"), requirePermission("mapa_areas.ver"), requireResourceScope("ubicacion", "ubicacionId"), controller.agregarElemento);
router.get("/ubicaciones/:ubicacionId/elementos", requirePermission("mapa_areas.ver"), requireResourceScope("ubicacion", "ubicacionId"), controller.listarElementos);
router.get("/ubicaciones/:ubicacionId/elementos/buscar", requirePermission("mapa_areas.ver"), requireResourceScope("ubicacion", "ubicacionId"), controller.buscarElementoPorNombre);

export default router;
