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
                    empresaId_herramientaId_estado: {
                        empresaId: data.empresaId,
                        herramientaId: creada.id,
                        estado: "OPERATIVA",
                    },
                },
                create: {
                    empresaId: data.empresaId,
                    herramientaId: creada.id,
                    cantidad: 0,
                    estado: "OPERATIVA",
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
                stockEmpresa: item.stocksEmpresa.reduce((total, stock) => total + Number(stock.cantidad), 0),
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
        return this.prisma.$transaction(async (tx) => {
            const [stockEmpresa, stockConjunto, solicitudesItems, usosTarea, prestamos] = await Promise.all([
                tx.empresaHerramientaStock.findMany({
                    where: { herramientaId },
                    select: { id: true, cantidad: true },
                }),
                tx.conjuntoHerramientaStock.findMany({
                    where: { herramientaId },
                    select: { id: true, cantidad: true },
                }),
                tx.solicitudHerramientaItem.count({ where: { herramientaId } }),
                tx.usoHerramienta.count({ where: { herramientaId } }),
                tx.prestamoHerramientaConjunto.count({ where: { herramientaId } }),
            ]);
            const stockEmpresaActivo = stockEmpresa.some((row) => Number(row.cantidad) > 0);
            const stockConjuntoActivo = stockConjunto.some((row) => Number(row.cantidad) > 0);
            if (stockEmpresaActivo ||
                stockConjuntoActivo ||
                solicitudesItems > 0 ||
                usosTarea > 0 ||
                prestamos > 0) {
                const e = new Error("No fue posible eliminar la herramienta porque tiene movimientos o registros asociados.");
                e.status = 409;
                throw e;
            }
            if (stockConjunto.length) {
                await tx.conjuntoHerramientaStock.deleteMany({ where: { herramientaId } });
            }
            if (stockEmpresa.length) {
                await tx.empresaHerramientaStock.deleteMany({ where: { herramientaId } });
            }
            return tx.herramienta.delete({ where: { id: herramientaId } });
        });
    }
}
exports.HerramientaService = HerramientaService;
