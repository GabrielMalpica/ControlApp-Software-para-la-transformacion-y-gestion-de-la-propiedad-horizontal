// src/routes/gerente.ts
import { Router } from "express";
import { GerenteController } from "../controller/GerenteController";

const router = Router();
const controller = new GerenteController();

// Usuarios
router.post("/usuarios", controller.crearUsuario);
router.put("/usuarios/:id", controller.editarUsuario);

// Roles / Perfiles
router.post("/roles/gerente", controller.asignarGerente);
router.post("/roles/administrador", controller.asignarAdministrador);
router.post("/roles/jefe-operaciones", controller.asignarJefeOperaciones);
router.post("/roles/supervisor", controller.asignarSupervisor);
router.post("/roles/operario", controller.asignarOperario);

// Conjuntos
router.post("/conjuntos", controller.crearConjunto);
router.put("/conjuntos/:conjuntoId", controller.editarConjunto);
router.post("/conjuntos/:conjuntoId/operarios", controller.asignarOperarioAConjunto);

// Inventario / Insumos
router.post("/conjuntos/:conjuntoId/inventario/insumos", controller.agregarInsumoAConjunto);

// Maquinaria
router.post("/maquinaria", controller.crearMaquinaria);
router.put("/maquinaria/:maquinariaId", controller.editarMaquinaria);
router.post("/maquinaria/entregar", controller.entregarMaquinariaAConjunto); 
// (si prefieres REST puro:
//  router.post("/conjuntos/:conjuntoId/maquinaria/:maquinariaId/entregar", controller.entregarMaquinariaAConjunto);
//  y en el controller parseas params y construyes el payload)

// Tareas
router.post("/tareas", controller.asignarTarea);
router.put("/tareas/:tareaId", controller.editarTarea);

// Eliminaciones con reglas
router.delete("/administradores/:adminId", controller.eliminarAdministrador);
router.patch("/conjuntos/reemplazar-admines", controller.reemplazarAdminEnVariosConjuntos);
router.delete("/operarios/:operarioId", controller.eliminarOperario);
router.delete("/supervisores/:supervisorId", controller.eliminarSupervisor);
router.delete("/conjuntos/:conjuntoId", controller.eliminarConjunto);
router.delete("/maquinaria/:maquinariaId", controller.eliminarMaquinaria);
router.delete("/tareas/:tareaId", controller.eliminarTarea);

// Ediciones rápidas
router.put("/administradores/:adminId", controller.editarAdministrador);
router.put("/operarios/:operarioId", controller.editarOperario);
router.put("/supervisores/:supervisorId", controller.editarSupervisor);

export default router;
