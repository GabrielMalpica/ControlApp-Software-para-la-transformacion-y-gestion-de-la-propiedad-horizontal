import { Router } from "express";
import { ConjuntoController } from "../controller/ConjuntoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";
import { uploadImagenMemoria } from "../middlewares/upload_evidencias";


const c = new ConjuntoController();
export const conjuntoRouter = Router();

conjuntoRouter.use(authRequired);

conjuntoRouter.put("/conjuntos/:nit/activo", requireRoles("gerente"), requirePermission("conjuntos.gestionar"), requireConjuntoScope("nit"), c.setActivo);

conjuntoRouter.post("/conjuntos/:nit/operarios", requireRoles("gerente"), requirePermission("conjuntos.gestionar"), requireConjuntoScope("nit"), c.asignarOperario);
conjuntoRouter.put("/conjuntos/:nit/administrador", requireRoles("gerente"), requirePermission("conjuntos.gestionar"), requireConjuntoScope("nit"), c.asignarAdministrador);
conjuntoRouter.delete("/conjuntos/:nit/administrador", requireRoles("gerente"), requirePermission("conjuntos.gestionar"), requireConjuntoScope("nit"), c.eliminarAdministrador);

conjuntoRouter.post("/conjuntos/:nit/maquinaria", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireConjuntoScope("nit"), c.agregarMaquinaria);
conjuntoRouter.post("/conjuntos/:nit/maquinaria/entregar", requireRoles("gerente", "jefe_operaciones"), requirePermission("maquinaria.asignar"), requireConjuntoScope("nit"), c.entregarMaquinaria);
conjuntoRouter.get("/:nit/maquinaria", requirePermission("maquinaria.ver"), requireConjuntoScope("nit"), c.listarMaquinaria);
conjuntoRouter.get(
  "/conjuntos/:nit/mapa",
  requirePermission("mapa_areas.ver"),
  requireConjuntoScope("nit"),
  c.obtenerDetalleMapa,
);
conjuntoRouter.get(
  "/conjuntos/:nit/mapa/archivo",
  requirePermission("mapa_areas.ver"),
  requireConjuntoScope("nit"),
  c.obtenerMapaArchivo,
);
conjuntoRouter.put(
  "/conjuntos/:nit/mapa",
  requireRoles("gerente", "jefe_operaciones"),
  requirePermission("mapa_areas.ver"),
  requireConjuntoScope("nit"),
  uploadImagenMemoria.single("file"),
  c.actualizarMapa,
);

conjuntoRouter.post("/conjuntos/:nit/ubicaciones", requireRoles("gerente", "jefe_operaciones"), requirePermission("mapa_areas.ver"), requireConjuntoScope("nit"), c.agregarUbicacion);
conjuntoRouter.get("/conjuntos/:nit/ubicaciones/buscar", requirePermission("mapa_areas.ver"), requireConjuntoScope("nit"), c.buscarUbicacion);

conjuntoRouter.post("/conjuntos/:nit/cronograma/tareas", requireRoles("gerente", "jefe_operaciones", "supervisor"), requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireConjuntoScope("nit"), c.agregarTareaACronograma);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-fecha", requirePermission("tareas.ver", "cronograma.ver"), requireConjuntoScope("nit"), c.tareasPorFecha);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-operario/:operarioId", requirePermission("tareas.ver", "cronograma.ver"), requireConjuntoScope("nit"), requireResourceScope("operario", "operarioId"), c.tareasPorOperario);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-ubicacion", requirePermission("tareas.ver", "cronograma.ver"), requireConjuntoScope("nit"), c.tareasPorUbicacion);
conjuntoRouter.get("/conjuntos/:nit/tareas/en-rango", requirePermission("tareas.ver", "cronograma.ver"), requireConjuntoScope("nit"), c.tareasEnRango);
conjuntoRouter.get("/conjuntos/:nit/tareas/filtrar", requirePermission("tareas.ver", "cronograma.ver"), requireConjuntoScope("nit"), c.tareasPorFiltro);
conjuntoRouter.get("/conjuntos/:nit/cronograma/eventos-calendario", requirePermission("cronograma.ver"), requireConjuntoScope("nit"), c.exportarEventosCalendario);

export default conjuntoRouter;
