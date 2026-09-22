// ejemplo: src/routes/Inventario.ts
import { Router } from "express";
import { InventarioController } from "../controller/InventarioController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";
import { requireEmpresaScope } from "../middlewares/tenant.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { InventarioActivoController } from "../controller/InventarioActivoController";
import { uploadFotoInventario } from "../middlewares/upload_evidencias";

const router = Router();
const c = new InventarioController();
const activos = new InventarioActivoController();

router.use(authRequired);

// Inventario físico de maquinaria y herramientas. Estas rutas se declaran
// antes de las rutas legacy por inventarioId para evitar ambigüedades.
router.get("/empresa/:empresaId/resumen", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("inventario.ver"), requireEmpresaScope("empresaId"), activos.resumenEmpresa);
router.get("/conjunto/:nit/resumen", requirePermission("inventario.ver"), requireConjuntoScope("nit"), activos.resumenConjunto);
router.get("/empresa/:empresaId/catalogos/maquinaria", requirePermission("maquinaria.ver"), requireEmpresaScope("empresaId"), activos.catalogoMaquinaria);
router.get("/empresa/:empresaId/catalogos/herramientas", requirePermission("herramientas.ver"), requireEmpresaScope("empresaId"), activos.catalogoHerramientas);

router.get("/empresa/:empresaId/maquinaria", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.ver"), requireEmpresaScope("empresaId"), activos.listarMaquinariaEmpresa);
router.post("/empresa/:empresaId/maquinaria", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.crear"), requireEmpresaScope("empresaId"), activos.crearMaquinariaEmpresa);
router.get("/conjunto/:nit/maquinaria", requirePermission("maquinaria.ver"), requireConjuntoScope("nit"), activos.listarMaquinariaConjunto);
router.post("/conjunto/:nit/maquinaria", requirePermission("maquinaria.crear"), requireConjuntoScope("nit"), activos.crearMaquinariaConjunto);

router.get("/empresa/:empresaId/herramientas", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.ver"), requireEmpresaScope("empresaId"), activos.listarHerramientasEmpresa);
router.post("/empresa/:empresaId/herramientas", requireRoles("gerente", "jefe_operaciones"), requirePermission("herramientas.crear"), requireEmpresaScope("empresaId"), activos.crearHerramientasEmpresa);
router.get("/conjunto/:nit/herramientas", requirePermission("herramientas.ver"), requireConjuntoScope("nit"), activos.listarHerramientasConjunto);
router.post("/conjunto/:nit/herramientas", requirePermission("herramientas.crear"), requireConjuntoScope("nit"), activos.crearHerramientasConjunto);

for (const [path, kind, editPermission, approvalPermission, statePermission, loanPermission] of [
  ["maquinaria", "maquinaria", "maquinaria.editar", "maquinaria.aprobar", "maquinaria.gestionar_estado", "maquinaria.prestar"],
  ["herramientas", "herramienta", "herramientas.editar", "herramientas.aprobar", "herramientas.gestionar_estado", "herramientas.prestar"],
] as const) {
  router.patch(`/${path}/:id`, requirePermission(editPermission, `${path}.crear`), activos.editar(kind));
  router.post(`/${path}/:id/aprobar`, requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission(approvalPermission), activos.aprobar(kind));
  router.post(`/${path}/:id/rechazar`, requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission(approvalPermission), activos.rechazar(kind));
  router.post(`/${path}/:id/estado`, requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission(statePermission), activos.cambiarEstado(kind));
  router.post(`/${path}/:id/prestar`, requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission(loanPermission), activos.prestar(kind));
  router.post(`/${path}/:id/devolver`, requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission(loanPermission), activos.devolver(kind));
  router.get(`/${path}/:id/foto`, requirePermission(`${path}.ver`), activos.obtenerFoto(kind));
  router.put(`/${path}/:id/foto`, requirePermission(editPermission, `${path}.crear`), uploadFotoInventario.single("foto"), activos.guardarFoto(kind));
  router.delete(`/${path}/:id/foto`, requirePermission(editPermission, `${path}.crear`), activos.eliminarFoto(kind));
  router.delete(`/${path}/:id`, requireRoles("gerente"), activos.eliminar(kind));
}
router.post("/herramientas/lotes/:loteId/aprobar", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("herramientas.aprobar"), activos.aprobarLoteHerramientas);
router.post("/herramientas/lotes/:loteId/rechazar", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("herramientas.aprobar"), activos.rechazarLoteHerramientas);

// ✅ por conjunto
router.get("/conjunto/:nit/insumos", requirePermission("inventario.ver"), requireConjuntoScope("nit"), c.listarInsumosConjunto);
router.get(
  "/conjunto/:nit/insumos-bajos",
  requirePermission("inventario.ver"),
  requireConjuntoScope("nit"),
  c.listarInsumosBajosConjunto,
);
router.post(
  "/conjunto/:nit/insumos-personalizados",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("inventario.gestionar"),
  requireConjuntoScope("nit"),
  c.crearInsumoPersonalizadoConjunto,
);
router.patch(
  "/conjunto/:nit/insumos-personalizados/:insumoId",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("inventario.gestionar"),
  requireConjuntoScope("nit"),
  c.editarInsumoPersonalizadoConjunto,
);
router.delete(
  "/conjunto/:nit/insumos-personalizados/:insumoId",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("inventario.gestionar"),
  requireConjuntoScope("nit"),
  c.eliminarInsumoPersonalizadoConjunto,
);
router.post("/conjunto/:nit/agregar-stock", requirePermission("inventario.gestionar"), requireConjuntoScope("nit"), c.agregarStockConjunto);
router.post(
  "/conjunto/:nit/consumir-stock",
  requirePermission("inventario.gestionar"),
  requireConjuntoScope("nit"),
  c.consumirStockConjunto,
);
router.get("/conjunto/:nit/insumos/:insumoId", requirePermission("inventario.ver"), requireConjuntoScope("nit"), c.buscarInsumoConjunto);
router.get(
  "/conjunto/:nit/insumos/:insumoId/movimientos",
  requirePermission("inventario.ver"),
  requireConjuntoScope("nit"),
  c.listarMovimientosInsumoConjunto,
);

// ✅ legacy por inventarioId (si aún los usas)
router.post("/:inventarioId/insumos", requirePermission("inventario.gestionar"), requireResourceScope("inventario", "inventarioId"), c.agregarInsumo);
router.get("/:inventarioId/insumos", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.listarInsumos);
router.delete("/:inventarioId/insumos/:insumoId", requirePermission("inventario.gestionar"), requireResourceScope("inventario", "inventarioId"), c.eliminarInsumo);
router.get("/:inventarioId/insumos/:insumoId", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.buscarInsumoPorId);
router.post(
  "/:inventarioId/insumos/:insumoId/consumir",
  requirePermission("inventario.gestionar"),
  requireResourceScope("inventario", "inventarioId"),
  c.consumirInsumoPorId,
);
router.get("/:inventarioId/insumos-bajos", requirePermission("inventario.ver"), requireResourceScope("inventario", "inventarioId"), c.listarInsumosBajos);

export default router;
