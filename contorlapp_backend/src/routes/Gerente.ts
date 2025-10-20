// src/routes/gerente.routes.ts
import { Router } from "express";
import { GerenteController } from "../controller/GerenteController";

const router = Router();
const ctrl = new GerenteController();

/* Empresa */
router.post("/empresa", ctrl.crearEmpresa);
router.patch("/empresa/limite-horas", ctrl.actualizarLimiteHoras); // opcional

/* Catálogo insumos (empresa) */
router.post("/empresa/insumos", ctrl.agregarInsumoAlCatalogo);
router.get("/empresa/insumos", ctrl.listarCatalogoInsumos);

/* Usuarios */
router.post("/usuarios", ctrl.crearUsuario);
router.patch("/usuarios/:id", ctrl.editarUsuario);

/* Roles / perfiles */
router.post("/gerentes", ctrl.asignarGerente);
router.post("/administradores", ctrl.asignarAdministrador);
router.post("/jefes-operaciones", ctrl.asignarJefeOperaciones);
router.post("/supervisores", ctrl.asignarSupervisor);
router.post("/operarios", ctrl.asignarOperario);

/* Conjuntos */
router.post("/conjuntos", ctrl.crearConjunto);
router.patch("/conjuntos/:conjuntoId", ctrl.editarConjunto);
router.post("/conjuntos/:conjuntoId/operarios", ctrl.asignarOperarioAConjunto);
router.post("/conjuntos/:conjuntoId/insumos", ctrl.agregarInsumoAConjunto);

/* Maquinaria */
router.post("/maquinaria", ctrl.crearMaquinaria);
router.patch("/maquinaria/:maquinariaId", ctrl.editarMaquinaria);
router.post("/maquinaria/entregar", ctrl.entregarMaquinariaAConjunto); // si prefieres por URL, cámbialo

/* Tareas */
router.post("/tareas", ctrl.asignarTarea);
router.patch("/tareas/:tareaId", ctrl.editarTarea);

/* Eliminaciones con reglas */
router.delete("/administradores/:adminId", ctrl.eliminarAdministrador);
router.post("/administradores/reemplazos", ctrl.reemplazarAdminEnVariosConjuntos);

router.delete("/operarios/:operarioId", ctrl.eliminarOperario);
router.delete("/supervisores/:supervisorId", ctrl.eliminarSupervisor);

router.delete("/conjuntos/:conjuntoId", ctrl.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", ctrl.eliminarMaquinaria);
router.delete("/tareas/:tareaId", ctrl.eliminarTarea);

/* Ediciones rápidas */
router.patch("/administradores/:adminId", ctrl.editarAdministrador);
router.patch("/operarios/:operarioId", ctrl.editarOperario);
router.patch("/supervisores/:supervisorId", ctrl.editarSupervisor);

export default router;
