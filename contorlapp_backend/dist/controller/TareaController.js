"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TareaController = void 0;
const prisma_1 = require("../db/prisma");
const zod_1 = require("zod");
const TareaServices_1 = require("../services/TareaServices");
const IdParamSchema = zod_1.z.object({
    id: zod_1.z.coerce.number().int().positive(),
});
class TareaController {
    constructor() {
        // POST /tareas  (correctiva por defecto)
        this.crearTarea = async (req, res, next) => {
            try {
                const creada = await TareaServices_1.TareaService.crearTareaCorrectiva(prisma_1.prisma, req.body);
                res.status(201).json(creada);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /tareas
        this.listarTareas = async (req, res, next) => {
            try {
                const list = await TareaServices_1.TareaService.listarTareas(prisma_1.prisma, req.query);
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /tareas/:id
        this.obtenerTarea = async (req, res, next) => {
            try {
                const { id } = IdParamSchema.parse(req.params);
                const tarea = await TareaServices_1.TareaService.obtenerTarea(prisma_1.prisma, id);
                res.json(tarea);
            }
            catch (err) {
                next(err);
            }
        };
        // PATCH /tareas/:id
        this.editarTarea = async (req, res, next) => {
            try {
                const { id } = IdParamSchema.parse(req.params);
                const tarea = await TareaServices_1.TareaService.editarTarea(prisma_1.prisma, id, req.body);
                res.json(tarea);
            }
            catch (err) {
                next(err);
            }
        };
        // DELETE /tareas/:id
        this.eliminarTarea = async (req, res, next) => {
            try {
                const { id } = IdParamSchema.parse(req.params);
                await TareaServices_1.TareaService.eliminarTarea(prisma_1.prisma, id);
                res.status(204).send();
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.TareaController = TareaController;
