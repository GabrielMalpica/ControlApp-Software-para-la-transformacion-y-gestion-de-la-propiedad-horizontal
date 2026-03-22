"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaStockService = void 0;
class HerramientaStockService {
    constructor(prisma, conjuntoId) {
        this.prisma = prisma;
        this.conjuntoId = conjuntoId;
    }
    async listarStockEmpresa(empresaId) {
        return this.prisma.empresaHerramientaStock.findMany({
            where: { empresaId },
            include: { herramienta: true },
            orderBy: { herramienta: { nombre: "asc" } },
        });
    }
    async upsertStockEmpresa(data) {
        return this.prisma.empresaHerramientaStock.upsert({
            where: {
                empresaId_herramientaId: {
                    empresaId: data.empresaId,
                    herramientaId: data.herramientaId,
                },
            },
            create: {
                empresaId: data.empresaId,
                herramientaId: data.herramientaId,
                cantidad: data.cantidad,
            },
            update: {
                cantidad: data.cantidad,
            },
            include: { herramienta: true },
        });
    }
    async ajustarStockEmpresa(data) {
        return this.prisma.$transaction(async (tx) => {
            const row = await tx.empresaHerramientaStock.findUnique({
                where: {
                    empresaId_herramientaId: {
                        empresaId: data.empresaId,
                        herramientaId: data.herramientaId,
                    },
                },
            });
            if (!row) {
                const e = new Error("No existe stock de empresa para esa herramienta");
                e.status = 404;
                throw e;
            }
            const nuevaCantidad = Number(row.cantidad) + Number(data.delta);
            if (nuevaCantidad < 0) {
                const e = new Error("Stock de empresa insuficiente");
                e.status = 409;
                throw e;
            }
            return tx.empresaHerramientaStock.update({
                where: {
                    empresaId_herramientaId: {
                        empresaId: data.empresaId,
                        herramientaId: data.herramientaId,
                    },
                },
                data: { cantidad: nuevaCantidad },
                include: { herramienta: true },
            });
        });
    }
    async eliminarStockEmpresa(data) {
        return this.prisma.empresaHerramientaStock.delete({
            where: {
                empresaId_herramientaId: {
                    empresaId: data.empresaId,
                    herramientaId: data.herramientaId,
                },
            },
        });
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
    async listarDisponibilidad(params) {
        const { empresaId, fechaInicio, fechaFin, excluirTareaId } = params;
        const [catalogo, stockConjunto, stockEmpresa, reservas] = await Promise.all([
            this.prisma.herramienta.findMany({
                where: { empresaId },
                orderBy: { nombre: "asc" },
            }),
            this.prisma.conjuntoHerramientaStock.findMany({
                where: { conjuntoId: this.conjuntoId, estado: "OPERATIVA" },
                select: { herramientaId: true, cantidad: true },
            }),
            this.prisma.empresaHerramientaStock.findMany({
                where: { empresaId },
                select: { herramientaId: true, cantidad: true },
            }),
            fechaInicio && fechaFin
                ? this.prisma.usoHerramienta.findMany({
                    where: {
                        fechaInicio: { lt: fechaFin },
                        OR: [{ fechaFin: null }, { fechaFin: { gt: fechaInicio } }],
                        estado: { in: ["RESERVADA", "EN_USO"] },
                        ...(excluirTareaId ? { tareaId: { not: excluirTareaId } } : {}),
                        tarea: {
                            estado: {
                                notIn: [
                                    "COMPLETADA",
                                    "NO_COMPLETADA",
                                    "CANCELADA",
                                ],
                            },
                        },
                    },
                    select: {
                        herramientaId: true,
                        cantidad: true,
                        origenStock: true,
                    },
                })
                : Promise.resolve([]),
        ]);
        const conjuntoMap = new Map(stockConjunto.map((r) => [r.herramientaId, Number(r.cantidad)]));
        const empresaMap = new Map(stockEmpresa.map((r) => [r.herramientaId, Number(r.cantidad)]));
        const reservadas = new Map();
        for (const r of reservas) {
            const key = `${r.herramientaId}:${r.origenStock}`;
            reservadas.set(key, (reservadas.get(key) ?? 0) + Number(r.cantidad));
        }
        return catalogo.map((h) => {
            const stockConjuntoTotal = Number(conjuntoMap.get(h.id) ?? 0);
            const stockEmpresaTotal = Number(empresaMap.get(h.id) ?? 0);
            const reservadoConjunto = Number(reservadas.get(`${h.id}:CONJUNTO`) ?? 0);
            const reservadoEmpresa = Number(reservadas.get(`${h.id}:EMPRESA`) ?? 0);
            const disponibleConjunto = Math.max(0, stockConjuntoTotal - reservadoConjunto);
            const disponibleEmpresa = Math.max(0, stockEmpresaTotal - reservadoEmpresa);
            return {
                herramientaId: h.id,
                nombre: h.nombre,
                unidad: h.unidad,
                categoria: h.categoria ?? "OTROS",
                modoControl: h.modoControl,
                umbralBajo: h.umbralBajo,
                stockConjunto: stockConjuntoTotal,
                stockEmpresa: stockEmpresaTotal,
                reservadoConjunto,
                reservadoEmpresa,
                disponibleConjunto,
                disponibleEmpresa,
                totalDisponible: disponibleConjunto + disponibleEmpresa,
            };
        });
    }
}
exports.HerramientaStockService = HerramientaStockService;
