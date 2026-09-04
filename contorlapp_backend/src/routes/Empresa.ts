// src/routes/empresas.ts
import { Router } from "express";
import { EmpresaController } from "../controller/EmpresaController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireEmpresaScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();
const controller = new EmpresaController();

router.use(authRequired);

// Empresa
router.post("/", requireRoles("gerente"), requirePermission("empresa.gestionar"), controller.crearEmpresa);
router.get("/:nit/limite-min-semana", requirePermission("cronograma.ver"), requireEmpresaScope("nit"), controller.getLimiteMinSemanaPorConjunto);
router.get("/festivos", requirePermission("cronograma.ver"), controller.listarFestivos);
router.put("/festivos/rango", requirePermission("cronograma.publicar"), controller.reemplazarFestivosEnRango);

// Maquinaria
router.post("/:nit/maquinaria", requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), controller.agregarMaquinaria);
router.get("/:nit/maquinaria/disponible", requirePermission("maquinaria.ver", "maquinaria.asignar"), requireEmpresaScope("nit"), controller.listarMaquinariaDisponible);
router.get("/:nit/maquinaria/prestada", requirePermission("maquinaria.ver", "maquinaria.asignar"), requireEmpresaScope("nit"), controller.obtenerMaquinariaPrestada);
router.get("/:nit/maquinaria", requirePermission("maquinaria.ver", "maquinaria.asignar"), requireEmpresaScope("nit"), controller.listarMaquinariaCatalogo);
router.patch("/:nit/maquinaria/:id", requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), requireResourceScope("maquinaria", "id"), controller.editarMaquinaria);
router.delete("/:nit/maquinaria/:id", requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), requireResourceScope("maquinaria", "id"), controller.eliminarMaquinaria);

// Jefe de Operaciones
router.post("/:nit/jefe-operaciones", requireRoles("gerente"), requirePermission("usuarios.gestionar"), requireEmpresaScope("nit"), controller.agregarJefeOperaciones);

// Solicitudes de tarea
router.patch("/:nit/solicitudes-tarea/:id/recibir", requirePermission("solicitudes.gestionar"), requireEmpresaScope("nit"), requireResourceScope("solicitudTarea", "id"), controller.recibirSolicitudTarea);
router.delete("/:nit/solicitudes-tarea/:id", requirePermission("solicitudes.gestionar"), requireEmpresaScope("nit"), requireResourceScope("solicitudTarea", "id"), controller.eliminarSolicitudTarea);
router.get("/:nit/solicitudes-tarea/pendientes", requirePermission("solicitudes.ver"), requireEmpresaScope("nit"), controller.solicitudesTareaPendientes);

// Catálogo de insumos
router.post("/:nit/catalogo/insumos", requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), controller.agregarInsumoAlCatalogo);
router.get("/:nit/catalogo", requirePermission("inventario.ver", "inventario.gestionar"), requireEmpresaScope("nit"), controller.listarCatalogo);
router.get("/:nit/catalogo/insumos/:id", requirePermission("inventario.ver", "inventario.gestionar"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.buscarInsumoPorId);
router.patch("/:nit/catalogo/insumos/:id", requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.editarInsumoCatalogo);
router.delete("/:nit/catalogo/insumos/:id", requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.eliminarInsumoCatalogo);

export default router;
