"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.UbicacionController = void 0;
const zod_1 = require("zod");
const prisma_1 = require("../db/prisma");
const UbicacionServices_1 = require("../services/UbicacionServices");
const UbicacionIdParam = zod_1.z.object({ ubicacionId: zod_1.z.coerce.number().int().positive() });
const ElementoBody = zod_1.z.object({ nombre: zod_1.z.string().min(1) });
const BuscarQuery = zod_1.z.object({ nombre: zod_1.z.string().min(1) });
class UbicacionController {
    constructor() {
        // POST /ubicaciones/:ubicacionId/elementos
        this.agregarElemento = async (req, res, next) => {
            try {
                const { ubicacionId } = UbicacionIdParam.parse(req.params);
                const body = ElementoBody.parse(req.body);
                const service = new UbicacionServices_1.UbicacionService(prisma_1.prisma, ubicacionId);
                await service.agregarElemento(body);
                res.status(201).json({ message: "Elemento creado" });
            }
            catch (err) {
                next(err);
            }
        };
        // GET /ubicaciones/:ubicacionId/elementos
        this.listarElementos = async (_req, res, next) => {
            try {
                const { ubicacionId } = UbicacionIdParam.parse(_req.params);
                const service = new UbicacionServices_1.UbicacionService(prisma_1.prisma, ubicacionId);
                const list = await service.listarElementos();
                res.json(list);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /ubicaciones/:ubicacionId/elementos/buscar?nombre=...
        this.buscarElementoPorNombre = async (req, res, next) => {
            try {
                const { ubicacionId } = UbicacionIdParam.parse(req.params);
                const { nombre } = BuscarQuery.parse(req.query);
                const service = new UbicacionServices_1.UbicacionService(prisma_1.prisma, ubicacionId);
                const item = await service.buscarElementoPorNombre({ nombre });
                if (!item) {
                    res.status(404).json({ message: "Elemento no encontrado" });
                    return;
                }
                res.json(item);
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.UbicacionController = UbicacionController;
