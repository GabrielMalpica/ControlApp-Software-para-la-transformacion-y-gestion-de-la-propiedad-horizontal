"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SolicitudHerramientaService = void 0;
const SolicitudHerramienta_1 = require("../model/SolicitudHerramienta");
class SolicitudHerramientaService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async crear(payload) {
        const dto = SolicitudHerramienta_1.CrearSolicitudHerramientaDTO.parse(payload);
        // ✅ Validar conjunto
        const conjunto = await this.prisma.conjunto.findUnique({
            where: { nit: dto.conjuntoId },
            select: { nit: true },
        });
        if (!conjunto)
            throw new Error("Conjunto no existe");
        // ✅ Validar herramientas
        const ids = dto.items.map((i) => i.herramientaId);
        const herramientas = await this.prisma.herramienta.findMany({
            where: { id: { in: ids } },
            select: { id: true },
        });
        if (herramientas.length !== ids.length)
            throw new Error("Una o más herramientas no existen");
        // Consolidar duplicados (por herramientaId + estado)
        const keyMap = new Map();
        for (const it of dto.items) {
            const estado = (it.estado ?? "OPERATIVA");
            const key = `${it.herramientaId}__${estado}`;
            keyMap.set(key, (keyMap.get(key) ?? 0) + Number(it.cantidad));
        }
        const itemsCreate = Array.from(keyMap.entries()).map(([key, cantidad]) => {
            const [herramientaIdStr, estado] = key.split("__");
            return {
                herramientaId: Number(herramientaIdStr),
                estado: estado, // si tu item tiene estado en el modelo; si NO, quítalo del create
                cantidad: cantidad,
            };
        });
        // ⚠️ Importante: tu modelo SolicitudHerramientaItem que te di antes NO tenía "estado".
        // Si tu schema NO tiene estado en SolicitudHerramientaItem, entonces en itemsCreate quitas "estado".
        // Y el estado se decide al aprobar (estadoIngreso).
        // --> Abajo te pongo la versión sin estado en item para que sea compatible con el schema que te pasé.
        return this.prisma.solicitudHerramienta.create({
            data: {
                conjuntoId: dto.conjuntoId,
                empresaId: dto.empresaId ?? null,
                estado: "PENDIENTE",
                items: {
                    create: dto.items.map((it) => ({
                        herramientaId: it.herramientaId,
                        cantidad: it.cantidad,
                    })),
                },
            },
            include: {
                items: {
                    include: {
                        herramienta: {
                            select: { nombre: true, unidad: true, modoControl: true },
                        },
                    },
                },
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
    }
    async aprobar(id, payload) {
        const dto = SolicitudHerramienta_1.AprobarSolicitudHerramientaDTO.parse(payload);
        return this.prisma.$transaction(async (tx) => {
            const sol = await tx.solicitudHerramienta.findUnique({
                where: { id },
                include: { items: true },
            });
            if (!sol)
                throw new Error("Solicitud no encontrada");
            if (sol.estado === "APROBADA")
                return sol;
            const estadoIngreso = (dto.estadoIngreso ?? "OPERATIVA");
            const empresaId = dto.empresaId ?? sol.empresaId;
            if (!empresaId) {
                throw new Error("La solicitud debe indicar la empresa que entrega la herramienta.");
            }
            for (const it of sol.items) {
                const herramienta = await tx.herramienta.findUnique({
                    where: { id: it.herramientaId },
                    select: { id: true, modoControl: true },
                });
                if (!herramienta) {
                    throw new Error(`Herramienta ${it.herramientaId} no encontrada.`);
                }
                const stockEmpresa = await tx.empresaHerramientaStock.findUnique({
                    where: {
                        empresaId_herramientaId: {
                            empresaId,
                            herramientaId: it.herramientaId,
                        },
                    },
                });
                const disponibleEmpresa = Number(stockEmpresa?.cantidad ?? 0);
                if (disponibleEmpresa < Number(it.cantidad)) {
                    throw new Error(`Stock insuficiente en empresa para la herramienta ${it.herramientaId}. Disponible: ${disponibleEmpresa}.`);
                }
                await tx.empresaHerramientaStock.update({
                    where: {
                        empresaId_herramientaId: {
                            empresaId,
                            herramientaId: it.herramientaId,
                        },
                    },
                    data: {
                        cantidad: { decrement: it.cantidad },
                    },
                });
                if (herramienta.modoControl === "PRESTAMO") {
                    await tx.prestamoHerramientaConjunto.create({
                        data: {
                            conjuntoId: sol.conjuntoId,
                            empresaId,
                            herramientaId: it.herramientaId,
                            solicitudId: sol.id,
                            cantidad: it.cantidad,
                            estado: estadoIngreso,
                            fechaInicio: dto.fechaAprobacion ?? new Date(),
                            fechaDevolucionEstimada: dto.fechaDevolucionEstimada ?? null,
                        },
                    });
                    continue;
                }
                await tx.conjuntoHerramientaStock.upsert({
                    where: {
                        conjuntoId_herramientaId_estado: {
                            conjuntoId: sol.conjuntoId,
                            herramientaId: it.herramientaId,
                            estado: estadoIngreso,
                        },
                    },
                    create: {
                        conjuntoId: sol.conjuntoId,
                        herramientaId: it.herramientaId,
                        estado: estadoIngreso,
                        cantidad: it.cantidad,
                    },
                    update: {
                        cantidad: { increment: it.cantidad },
                    },
                });
            }
            // ✅ actualizar solicitud
            return tx.solicitudHerramienta.update({
                where: { id },
                data: {
                    estado: "APROBADA",
                    fechaAprobacion: dto.fechaAprobacion ?? new Date(),
                    empresaId,
                },
                include: {
                    items: {
                        include: {
                            herramienta: {
                                select: { nombre: true, unidad: true, modoControl: true },
                            },
                        },
                    },
                    conjunto: { select: { nit: true, nombre: true } },
                },
            });
        });
    }
    async rechazar(id, payload) {
        // si quieres método espejo
        const { observacionRespuesta } = (payload ?? {});
        return this.prisma.solicitudHerramienta.update({
            where: { id },
            data: {
                estado: "RECHAZADA",
                observacionRespuesta: observacionRespuesta ?? null,
            },
            include: {
                items: {
                    include: {
                        herramienta: {
                            select: { nombre: true, unidad: true, modoControl: true },
                        },
                    },
                },
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
    }
    async listar(payload) {
        const f = SolicitudHerramienta_1.FiltroSolicitudHerramientaDTO.parse(payload);
        const rango = {};
        if (f.fechaDesde)
            rango.gte = f.fechaDesde;
        if (f.fechaHasta)
            rango.lte = f.fechaHasta;
        return this.prisma.solicitudHerramienta.findMany({
            where: {
                conjuntoId: f.conjuntoId ?? undefined,
                empresaId: f.empresaId ?? undefined,
                estado: f.estado ?? undefined,
                fechaSolicitud: Object.keys(rango).length ? rango : undefined,
            },
            include: {
                items: {
                    include: {
                        herramienta: {
                            select: { nombre: true, unidad: true, modoControl: true },
                        },
                    },
                },
                conjunto: { select: { nit: true, nombre: true } },
            },
            orderBy: { id: "desc" },
        });
    }
    async obtener(id) {
        return this.prisma.solicitudHerramienta.findUnique({
            where: { id },
            include: {
                items: {
                    include: {
                        herramienta: {
                            select: { nombre: true, unidad: true, modoControl: true },
                        },
                    },
                },
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
    }
    async eliminar(id) {
        await this.prisma.solicitudHerramienta.delete({ where: { id } });
    }
}
exports.SolicitudHerramientaService = SolicitudHerramientaService;
