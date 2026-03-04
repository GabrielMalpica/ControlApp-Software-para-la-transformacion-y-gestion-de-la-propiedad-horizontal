"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.InsumoController = void 0;
const prisma_1 = require("../db/prisma");
const Insumo_1 = require("../model/Insumo");
const EMPRESA_CORPORATIVA = "CORPORATIVO";
class InsumoController {
    constructor() {
        this.crear = async (req, res) => {
            const dto = Insumo_1.CrearInsumoDTO.parse(req.body);
            const empresaId = dto.empresaId ?? EMPRESA_CORPORATIVA;
            const existe = await prisma_1.prisma.insumo.findFirst({
                where: {
                    empresaId,
                    nombre: dto.nombre,
                    unidad: dto.unidad,
                },
                select: { id: true },
            });
            if (existe)
                throw new Error("Ya existe un insumo con ese nombre y unidad.");
            const creado = await prisma_1.prisma.insumo.create({
                data: {
                    nombre: dto.nombre,
                    unidad: dto.unidad,
                    empresaId,
                    categoria: dto.categoria,
                    umbralBajo: dto.umbralBajo ?? undefined,
                },
                select: Insumo_1.insumoPublicSelect,
            });
            res.status(201).json((0, Insumo_1.toInsumoPublico)(creado));
        };
        this.listar = async (req, res) => {
            const f = Insumo_1.FiltroInsumoDTO.parse(req.query);
            const where = {
                empresaId: (f.empresaId ?? EMPRESA_CORPORATIVA),
                nombre: f.nombre ? { contains: f.nombre, mode: "insensitive" } : undefined,
                categoria: f.categoria ?? undefined,
            };
            const items = await prisma_1.prisma.insumo.findMany({
                where,
                orderBy: { nombre: "asc" },
                select: Insumo_1.insumoPublicSelect,
            });
            res.json(items.map(Insumo_1.toInsumoPublico));
        };
    }
}
exports.InsumoController = InsumoController;
