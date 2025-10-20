import { Router } from "express";
import { PrismaClient } from "../generated/prisma";
import { ConjuntoController } from "../controller/ConjuntoController";

const prisma = new PrismaClient();
const c = new ConjuntoController(prisma);
export const conjuntoRouter = Router();

conjuntoRouter.put("/conjuntos/:nit/activo", c.setActivo);

conjuntoRouter.post("/conjuntos/:nit/operarios", c.asignarOperario);
conjuntoRouter.put("/conjuntos/:nit/administrador", c.asignarAdministrador);
conjuntoRouter.delete("/conjuntos/:nit/administrador", c.eliminarAdministrador);

conjuntoRouter.post("/conjuntos/:nit/maquinaria", c.agregarMaquinaria);
conjuntoRouter.post("/conjuntos/:nit/maquinaria/entregar", c.entregarMaquinaria);

conjuntoRouter.post("/conjuntos/:nit/ubicaciones", c.agregarUbicacion);
conjuntoRouter.get("/conjuntos/:nit/ubicaciones/buscar", c.buscarUbicacion);

conjuntoRouter.post("/conjuntos/:nit/cronograma/tareas", c.agregarTareaACronograma);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-fecha", c.tareasPorFecha);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-operario/:operarioId", c.tareasPorOperario);
conjuntoRouter.get("/conjuntos/:nit/tareas/por-ubicacion", c.tareasPorUbicacion);
conjuntoRouter.get("/conjuntos/:nit/tareas/en-rango", c.tareasEnRango);
conjuntoRouter.get("/conjuntos/:nit/tareas/filtrar", c.tareasPorFiltro);
conjuntoRouter.get("/conjuntos/:nit/cronograma/eventos-calendario", c.exportarEventosCalendario);
