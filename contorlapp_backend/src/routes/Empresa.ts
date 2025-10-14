// src/routes/empresas.ts
import { Router } from "express";
import { EmpresaController } from "../controller/EmpresaController";

const router = Router();
const controller = new EmpresaController();

// Empresa
router.post("/", controller.crearEmpresa);

// Maquinaria
router.post("/:nit/maquinaria", controller.agregarMaquinaria);
router.get("/:nit/maquinaria/disponible", controller.listarMaquinariaDisponible);
router.get("/:nit/maquinaria/prestada", controller.obtenerMaquinariaPrestada);

// Jefe de Operaciones
router.post("/:nit/jefe-operaciones", controller.agregarJefeOperaciones);

// Solicitudes de tarea
router.patch("/:nit/solicitudes-tarea/:id/recibir", controller.recibirSolicitudTarea);
router.delete("/:nit/solicitudes-tarea/:id", controller.eliminarSolicitudTarea);
router.get("/:nit/solicitudes-tarea/pendientes", controller.solicitudesTareaPendientes);

// Catálogo de insumos
router.post("/:nit/catalogo/insumos", controller.agregarInsumoAlCatalogo);
router.get("/:nit/catalogo", controller.listarCatalogo);
router.get("/:nit/catalogo/insumos/:id", controller.buscarInsumoPorId);

export default router;
