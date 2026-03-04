"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaStockService = void 0;
class HerramientaStockService {
    constructor(prisma, conjuntoId) {
        this.prisma = prisma;
        this.conjuntoId = conjuntoId;
    }
    async listarStock({ estado } = {}) {
        return this.prisma.conjuntoHerramientaStock.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                ...(estado ? { estado } : {}),
            },
            include: { herramienta: true },
            orderBy: { herramienta: { nombre: "asc" } },
        });
    }
    async upsertStock(data) {
        return this.prisma.conjuntoHerramientaStock.upsert({
            where: {
                conjuntoId_herramientaId_estado: {
                    conjuntoId: this.conjuntoId,
                    herramientaId: data.herramientaId,
                    estado: data.estado,
                },
            },
            create: {
                conjuntoId: this.conjuntoId,
                herramientaId: data.herramientaId,
                cantidad: data.cantidad,
                estado: data.estado,
            },
            update: {
                cantidad: data.cantidad,
            },
            include: { herramienta: true },
        });
    }
    async ajustarStock(data) {
        return this.prisma.$transaction(async (tx) => {
            const row = await tx.conjuntoHerramientaStock.findUnique({
                where: {
                    conjuntoId_herramientaId_estado: {
                        conjuntoId: this.conjuntoId,
                        herramientaId: data.herramientaId,
                        estado: data.estado,
                    },
                },
            });
            if (!row) {
                const e = new Error("No existe stock para esa herramienta/estado en este conjunto");
                e.status = 404;
                throw e;
            }
            const nuevaCantidad = Number(row.cantidad) + Number(data.delta);
            if (nuevaCantidad < 0) {
                const e = new Error("Stock insuficiente");
                e.status = 409;
                throw e;
            }
            return tx.conjuntoHerramientaStock.update({
                where: {
                    conjuntoId_herramientaId_estado: {
                        conjuntoId: this.conjuntoId,
                        herramientaId: data.herramientaId,
                        estado: data.estado,
                    },
                },
                data: { cantidad: nuevaCantidad },
                include: { herramienta: true },
            });
        });
    }
    async eliminarStock(data) {
        return this.prisma.conjuntoHerramientaStock.delete({
            where: {
                conjuntoId_herramientaId_estado: {
                    conjuntoId: this.conjuntoId,
                    herramientaId: data.herramientaId,
                    estado: data.estado,
                },
            },
        });
    }
}
exports.HerramientaStockService = HerramientaStockService;
