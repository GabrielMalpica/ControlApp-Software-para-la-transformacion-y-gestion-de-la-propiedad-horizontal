import { Router } from "express";

import { CatalogoOperativoController } from "../controller/CatalogoOperativoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const ctrl = new CatalogoOperativoController();

router.use(authRequired);

const ver = requirePermission("conjuntos.ver", "conjuntos.gestionar");
const gestionar = requirePermission("conjuntos.gestionar");

// Categorías de tarea (orden de programación del día)
router.get("/categorias", ver, ctrl.listarCategorias);
router.post("/categorias", gestionar, ctrl.crearCategoria);
router.put("/categorias/orden", gestionar, ctrl.reordenarCategorias);
router.patch("/categorias/:id", gestionar, requireResourceScope("categoriaTarea", "id"), ctrl.editarCategoria);
router.delete("/categorias/:id", gestionar, requireResourceScope("categoriaTarea", "id"), ctrl.eliminarCategoria);

// Perfiles operativos (capacidades = categorías permitidas)
router.get("/perfiles", ver, ctrl.listarPerfiles);
router.post("/perfiles", gestionar, ctrl.crearPerfil);
router.patch("/perfiles/:id", gestionar, requireResourceScope("perfilOperativo", "id"), ctrl.editarPerfil);
router.delete("/perfiles/:id", gestionar, requireResourceScope("perfilOperativo", "id"), ctrl.eliminarPerfil);

export default router;
