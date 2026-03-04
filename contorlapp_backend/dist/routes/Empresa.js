"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
// src/routes/empresas.ts
const express_1 = require("express");
const EmpresaController_1 = require("../controller/EmpresaController");
const router = (0, express_1.Router)();
const controller = new EmpresaController_1.EmpresaController();
// Empresa
router.post("/", controller.crearEmpresa);
router.get("/:nit/limite-min-semana", controller.getLimiteMinSemanaPorConjunto);
router.get("/festivos", controller.listarFestivos);
router.put("/festivos/rango", controller.reemplazarFestivosEnRango);
// Maquinaria
router.post("/:nit/maquinaria", controller.agregarMaquinaria);
router.get("/:nit/maquinaria/disponible", controller.listarMaquinariaDisponible);
router.get("/:nit/maquinaria/prestada", controller.obtenerMaquinariaPrestada);
router.get("/:nit/maquinaria", controller.listarMaquinariaCatalogo);
router.patch("/:nit/maquinaria/:id", controller.editarMaquinaria);
router.delete("/:nit/maquinaria/:id", controller.eliminarMaquinaria);
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
router.patch("/:nit/catalogo/insumos/:id", controller.editarInsumoCatalogo);
router.delete("/:nit/catalogo/insumos/:id", controller.eliminarInsumoCatalogo);
exports.default = router;
