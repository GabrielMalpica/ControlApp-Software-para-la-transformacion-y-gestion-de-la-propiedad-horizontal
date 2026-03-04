"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HerramientaService = void 0;
class HerramientaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async crear(data) {
        return this.prisma.herramienta.create({
            data: {
                empresaId: data.empresaId,
                nombre: data.nombre.trim(),
                unidad: data.unidad.trim(),
                modoControl: data.modoControl,
                vidaUtilDias: data.vidaUtilDias ?? null,
                umbralBajo: data.umbralBajo ?? null,
            },
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
                take: params.take,
                skip: params.skip,
            }),
        ]);
        return { total, data };
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
