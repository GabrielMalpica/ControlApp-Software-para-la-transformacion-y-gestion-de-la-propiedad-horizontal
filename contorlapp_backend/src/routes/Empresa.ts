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
router.get("/:nit/limite-min-semana", requireRoles("gerente", "jefe_operaciones"), requirePermission("cronograma.ver"), requireEmpresaScope("nit"), controller.getLimiteMinSemanaPorConjunto);
router.get("/festivos", requireRoles("gerente", "jefe_operaciones"), requirePermission("cronograma.ver"), controller.listarFestivos);
router.put("/festivos/rango", requireRoles("gerente", "jefe_operaciones"), requirePermission("cronograma.ver"), controller.reemplazarFestivosEnRango);

// Maquinaria
router.post("/:nit/maquinaria", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), controller.agregarMaquinaria);
router.get("/:nit/maquinaria/disponible", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.ver"), requireEmpresaScope("nit"), controller.listarMaquinariaDisponible);
router.get("/:nit/maquinaria/prestada", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.ver"), requireEmpresaScope("nit"), controller.obtenerMaquinariaPrestada);
router.get("/:nit/maquinaria", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.ver"), requireEmpresaScope("nit"), controller.listarMaquinariaCatalogo);
router.patch("/:nit/maquinaria/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), requireResourceScope("maquinaria", "id"), controller.editarMaquinaria);
router.delete("/:nit/maquinaria/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireEmpresaScope("nit"), requireResourceScope("maquinaria", "id"), controller.eliminarMaquinaria);

// Jefe de Operaciones
router.post("/:nit/jefe-operaciones", requireRoles("gerente"), requirePermission("usuarios.gestionar"), requireEmpresaScope("nit"), controller.agregarJefeOperaciones);

// Solicitudes de tarea
router.patch("/:nit/solicitudes-tarea/:id/recibir", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireEmpresaScope("nit"), requireResourceScope("solicitudTarea", "id"), controller.recibirSolicitudTarea);
router.delete("/:nit/solicitudes-tarea/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireEmpresaScope("nit"), requireResourceScope("solicitudTarea", "id"), controller.eliminarSolicitudTarea);
router.get("/:nit/solicitudes-tarea/pendientes", requireRoles("gerente", "jefe_operaciones"), requirePermission("solicitudes.ver"), requireEmpresaScope("nit"), controller.solicitudesTareaPendientes);

// Catálogo de insumos
router.post("/:nit/catalogo/insumos", requireRoles("gerente", "jefe_operaciones"), requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), controller.agregarInsumoAlCatalogo);
router.get("/:nit/catalogo", requireRoles("gerente", "jefe_operaciones"), requirePermission("inventario.ver"), requireEmpresaScope("nit"), controller.listarCatalogo);
router.get("/:nit/catalogo/insumos/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("inventario.ver"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.buscarInsumoPorId);
router.patch("/:nit/catalogo/insumos/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.editarInsumoCatalogo);
router.delete("/:nit/catalogo/insumos/:id", requireRoles("gerente", "jefe_operaciones"), requirePermission("inventario.gestionar"), requireEmpresaScope("nit"), requireResourceScope("insumo", "id"), controller.eliminarInsumoCatalogo);

export default router;
