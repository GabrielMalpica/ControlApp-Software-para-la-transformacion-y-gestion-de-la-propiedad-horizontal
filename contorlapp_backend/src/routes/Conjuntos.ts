import { Router } from "express";
import multer from "multer";
import { ConjuntoController } from "../controller/ConjuntoController";
import { authRequired } from "../middlewares/auth.middleware";
import { requireRoles } from "../middlewares/role.middleware";


const c = new ConjuntoController();
export const conjuntoRouter = Router();
const uploadMapa = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 10 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, cb) => {
    const mime = String(file.mimetype ?? "").toLowerCase();
    if (!mime.startsWith("image/")) {
      cb(new Error("Solo se permiten imagenes para el mapa del conjunto."));
      return;
    }
    cb(null, true);
  },
});

conjuntoRouter.put("/conjuntos/:nit/activo", c.setActivo);

conjuntoRouter.post("/conjuntos/:nit/operarios", c.asignarOperario);
conjuntoRouter.put("/conjuntos/:nit/administrador", c.asignarAdministrador);
conjuntoRouter.delete("/conjuntos/:nit/administrador", c.eliminarAdministrador);

conjuntoRouter.post("/conjuntos/:nit/maquinaria", c.agregarMaquinaria);
conjuntoRouter.post("/conjuntos/:nit/maquinaria/entregar", c.entregarMaquinaria);
conjuntoRouter.get("/:nit/maquinaria", c.listarMaquinaria);
conjuntoRouter.get("/conjuntos/:nit/mapa", authRequired, c.obtenerDetalleMapa);
conjuntoRouter.get(
  "/conjuntos/:nit/mapa/archivo",
  authRequired,
  c.obtenerMapaArchivo,
);
conjuntoRouter.put(
  "/conjuntos/:nit/mapa",
  authRequired,
  requireRoles("gerente", "jefe_operaciones"),
  uploadMapa.single("file"),
  c.actualizarMapa,
);

conjuntoRouter.post("/conjuntos/:nit/ubicaciones", c.agregarUbicacion);
conjuntoRouter.get("/conjuntos/:nit/ubicaciones/buscar", c.buscarUbicacion);

conjuntoRouter.post("/conjuntos/:nit/cronograma/tareas", c.agregarTareaACronograma);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-fecha", c.tareasPorFecha);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-operario/:operarioId", c.tareasPorOperario);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-ubicacion", c.tareasPorUbicacion);
conjuntoRouter.get("/conjuntos/:nit/tareas/en-rango", c.tareasEnRango);
conjuntoRouter.get("/conjuntos/:nit/tareas/filtrar", c.tareasPorFiltro);
conjuntoRouter.get("/conjuntos/:nit/cronograma/eventos-calendario", c.exportarEventosCalendario);

export default conjuntoRouter;
