"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.conjuntoRouter = void 0;
const express_1 = require("express");
const multer_1 = __importDefault(require("multer"));
const ConjuntoController_1 = require("../controller/ConjuntoController");
const auth_middleware_1 = require("../middlewares/auth.middleware");
const role_middleware_1 = require("../middlewares/role.middleware");
const c = new ConjuntoController_1.ConjuntoController();
exports.conjuntoRouter = (0, express_1.Router)();
const uploadMapa = (0, multer_1.default)({
    storage: multer_1.default.memoryStorage(),
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
exports.conjuntoRouter.put("/conjuntos/:nit/activo", c.setActivo);
exports.conjuntoRouter.post("/conjuntos/:nit/operarios", c.asignarOperario);
exports.conjuntoRouter.put("/conjuntos/:nit/administrador", c.asignarAdministrador);
exports.conjuntoRouter.delete("/conjuntos/:nit/administrador", c.eliminarAdministrador);
exports.conjuntoRouter.post("/conjuntos/:nit/maquinaria", c.agregarMaquinaria);
exports.conjuntoRouter.post("/conjuntos/:nit/maquinaria/entregar", c.entregarMaquinaria);
exports.conjuntoRouter.get("/:nit/maquinaria", c.listarMaquinaria);
exports.conjuntoRouter.get("/conjuntos/:nit/mapa", auth_middleware_1.authRequired, c.obtenerDetalleMapa);
exports.conjuntoRouter.get("/conjuntos/:nit/mapa/archivo", auth_middleware_1.authRequired, c.obtenerMapaArchivo);
exports.conjuntoRouter.put("/conjuntos/:nit/mapa", auth_middleware_1.authRequired, (0, role_middleware_1.requireRoles)("gerente", "jefe_operaciones"), uploadMapa.single("file"), c.actualizarMapa);
exports.conjuntoRouter.post("/conjuntos/:nit/ubicaciones", c.agregarUbicacion);
exports.conjuntoRouter.get("/conjuntos/:nit/ubicaciones/buscar", c.buscarUbicacion);
exports.conjuntoRouter.post("/conjuntos/:nit/cronograma/tareas", c.agregarTareaACronograma);
exports.conjuntoRouter.get("/conjuntos/:nit/tareas/por-fecha", c.tareasPorFecha);
exports.conjuntoRouter.get("/conjuntos/:nit/tareas/por-operario/:operarioId", c.tareasPorOperario);
exports.conjuntoRouter.get("/conjuntos/:nit/tareas/por-ubicacion", c.tareasPorUbicacion);
exports.conjuntoRouter.get("/conjuntos/:nit/tareas/en-rango", c.tareasEnRango);
exports.conjuntoRouter.get("/conjuntos/:nit/tareas/filtrar", c.tareasPorFiltro);
exports.conjuntoRouter.get("/conjuntos/:nit/cronograma/eventos-calendario", c.exportarEventosCalendario);
exports.default = exports.conjuntoRouter;
