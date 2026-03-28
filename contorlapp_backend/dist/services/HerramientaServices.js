"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaService = void 0;
class HerramientaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async crear(data) {
        return this.prisma.$transaction(async (tx) => {
            const creada = await tx.herramienta.create({
                data: {
                    empresaId: data.empresaId,
                    nombre: data.nombre.trim(),
                    unidad: data.unidad.trim(),
                    categoria: data.categoria,
                    modoControl: data.modoControl,
                    vidaUtilDias: data.vidaUtilDias ?? null,
                    umbralBajo: data.umbralBajo ?? null,
                },
            });
            await tx.empresaHerramientaStock.upsert({
                where: {
                    empresaId_herramientaId: {
                        empresaId: data.empresaId,
                        herramientaId: creada.id,
                    },
                },
                create: {
                    empresaId: data.empresaId,
                    herramientaId: creada.id,
                    cantidad: 0,
                },
                update: {},
            });
            return creada;
        });
    }
    async listar(params) {
        const where = { empresaId: params.empresaId };
        if (params.nombre?.trim()) {
            where.nombre = { contains: params.nombre.trim(), mode: "insensitive" };
        }
        const [total, data] = await Promise.all([
            this.prisma.herramienta.count({ where }),
            this.prisma.herramienta.findMany({
                where,
                orderBy: { nombre: "asc" },
                include: {
                    stocksEmpresa: {
                        where: { empresaId: params.empresaId },
                        select: { cantidad: true },
                        take: 1,
                    },
                },
                take: params.take,
                skip: params.skip,
            }),
        ]);
        return {
            total,
            data: data.map((item) => ({
                ...item,
                stockEmpresa: item.stocksEmpresa.length > 0 ? Number(item.stocksEmpresa[0].cantidad) : 0,
            })),
        };
    }
    async obtenerPorId(herramientaId) {
        const h = await this.prisma.herramienta.findUnique({
            where: { id: herramientaId },
        });
        if (!h) {
            const e = new Error("Herramienta no encontrada");
            e.status = 404;
            throw e;
        }
        return h;
    }
    async editar(herramientaId, data) {
        await this.obtenerPorId(herramientaId);
        return this.prisma.herramienta.update({
            where: { id: herramientaId },
            data: {
                ...(data.nombre !== undefined ? { nombre: data.nombre.trim() } : {}),
                ...(data.unidad !== undefined ? { unidad: data.unidad.trim() } : {}),
                ...(data.categoria !== undefined ? { categoria: data.categoria } : {}),
                ...(data.modoControl !== undefined
                    ? { modoControl: data.modoControl }
                    : {}),
                ...(data.vidaUtilDias !== undefined
                    ? { vidaUtilDias: data.vidaUtilDias }
                    : {}),
                ...(data.umbralBajo !== undefined
                    ? { umbralBajo: data.umbralBajo }
                    : {}),
            },
        });
    }
    async eliminar(herramientaId) {
        await this.obtenerPorId(herramientaId);
        return this.prisma.herramienta.delete({ where: { id: herramientaId } });
    }
}
exports.HerramientaService = HerramientaService;
