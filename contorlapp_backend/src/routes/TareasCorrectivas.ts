import { Router } from "express";
import { TareaCorrectivaController } from "../controller/TareaCorrectivaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new TareaCorrectivaController();

router.use(authRequired);

// Crear correctiva
router.post("/conjuntos/:nit/tareas", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireConjuntoScope("nit"), controller.crear);

// Editar correctiva (el servicio la limita al alcance del rol)
router.patch("/tareas/:id", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireResourceScope("tarea", "id"), controller.editar);

// Listar por rango (mixto o filtra tipo), dentro del alcance de lectura del rol
router.get("/conjuntos/:nit/tareas", requirePermission("tareas.ver"), requireConjuntoScope("nit"), controller.listarPorConjunto);

export default router;
