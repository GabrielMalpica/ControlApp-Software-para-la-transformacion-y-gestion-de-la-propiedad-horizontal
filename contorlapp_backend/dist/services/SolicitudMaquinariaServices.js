"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudMaquinariaService = void 0;
const SolicitudMaquinaria_1 = require("../model/SolicitudMaquinaria");
class SolicitudMaquinariaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async crear(payload) {
        const dto = SolicitudMaquinaria_1.CrearSolicitudMaquinariaDTO.parse(payload);
        const [conjunto, maquinaria, operario] = await Promise.all([
            this.prisma.conjunto.findUnique({
                where: { nit: dto.conjuntoId },
                select: { nit: true },
            }),
            this.prisma.maquinaria.findUnique({
                where: { id: dto.maquinariaId },
                select: { id: true },
            }),
            this.prisma.operario.findUnique({
                where: { id: dto.operarioId },
                select: { id: true },
            }), // ✅ string
        ]);
        if (!conjunto)
            throw new Error("Conjunto no existe");
        if (!maquinaria)
            throw new Error("Maquinaria no existe");
        if (!operario)
            throw new Error("Operario no existe");
        return this.prisma.solicitudMaquinaria.create({
            data: {
                conjuntoId: dto.conjuntoId,
                maquinariaId: dto.maquinariaId,
                operarioId: dto.operarioId, // ✅ string
                empresaId: dto.empresaId ?? null,
                fechaUso: dto.fechaUso,
                fechaDevolucionEstimada: dto.fechaDevolucionEstimada,
            },
        });
    }
    async editar(id, payload) {
        const dto = SolicitudMaquinaria_1.EditarSolicitudMaquinariaDTO.parse(payload);
        return this.prisma.solicitudMaquinaria.update({
            where: { id },
            data: {
                maquinariaId: dto.maquinariaId ?? undefined,
                operarioId: dto.operarioId ?? undefined, // ✅ string | undefined
                empresaId: dto.empresaId === undefined ? undefined : dto.empresaId,
                fechaUso: dto.fechaUso ?? undefined,
                fechaDevolucionEstimada: dto.fechaDevolucionEstimada ?? undefined,
            },
        });
    }
    async aprobar(id, payload) {
        const dto = SolicitudMaquinaria_1.AprobarSolicitudMaquinariaDTO.parse(payload);
        return this.prisma.$transaction(async (tx) => {
            const sol = await tx.solicitudMaquinaria.findUnique({ where: { id } });
            if (!sol)
                throw new Error("Solicitud no encontrada");
            if (sol.estado === "APROBADA")
                return sol;
            const activa = await tx.maquinariaConjunto.findFirst({
                where: { maquinariaId: sol.maquinariaId, estado: "ACTIVA" },
                select: { id: true },
            });
            if (activa)
                throw new Error("La maquinaria no está disponible para préstamo");
            const asignacion = await tx.maquinariaConjunto.create({
                data: {
                    conjunto: { connect: { nit: sol.conjuntoId } },
                    maquinaria: { connect: { id: sol.maquinariaId } },
                    tipoTenencia: "PRESTADA",
                    estado: "ACTIVA",
                    fechaInicio: dto.fechaAprobacion ?? new Date(),
                    fechaDevolucionEstimada: sol.fechaDevolucionEstimada,
                    // ✅ ahora sí puedes usar relación responsable
                    ...(sol.operarioId
                        ? { responsable: { connect: { id: sol.operarioId } } }
                        : {}),
                    // ✅ y también conectar la solicitud (si tu relación existe así)
                    solicitudMaquinaria: { connect: { id: sol.id } },
                },
            });
            const updated = await tx.solicitudMaquinaria.update({
                where: { id },
                data: {
                    estado: "APROBADA",
                    fechaAprobacion: dto.fechaAprobacion ?? new Date(),
                },
            });
            return { solicitud: updated, asignacion };
        });
    }
    async listar(payload) {
        const f = SolicitudMaquinaria_1.FiltroSolicitudMaquinariaDTO.parse(payload);
        const rango = {};
        if (f.fechaDesde)
            rango.gte = f.fechaDesde;
        if (f.fechaHasta)
            rango.lte = f.fechaHasta;
        return this.prisma.solicitudMaquinaria.findMany({
            where: {
                conjuntoId: f.conjuntoId ?? undefined,
                empresaId: f.empresaId ?? undefined,
                maquinariaId: f.maquinariaId ?? undefined,
                operarioId: f.operarioId ?? undefined, // ✅ string
                // aprobado: f.aprobado ?? undefined,   // ❌ solo si existe en schema
                fechaSolicitud: Object.keys(rango).length > 0 ? rango : undefined,
            },
            orderBy: { id: "desc" },
        });
    }
    async obtener(id) {
        return this.prisma.solicitudMaquinaria.findUnique({ where: { id } });
    }
    async eliminar(id) {
        await this.prisma.solicitudMaquinaria.delete({ where: { id } });
    }
}
exports.SolicitudMaquinariaService = SolicitudMaquinariaService;
