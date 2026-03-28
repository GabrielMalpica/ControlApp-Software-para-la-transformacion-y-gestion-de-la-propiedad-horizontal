"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.OperarioService = void 0;
// src/services/OperarioService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const TareaServices_1 = require("./TareaServices");
const drive_evidencias_1 = require("../utils/drive_evidencias");
const fs_1 = __importDefault(require("fs"));
const NotificacionService_1 = require("./NotificacionService");
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
const TareaIdDTO = zod_1.z.object({ tareaId: zod_1.z.number().int().positive() });
const MarcarCompletadaDTO = zod_1.z.object({
    tareaId: zod_1.z.number().int().positive(),
    evidencias: zod_1.z.array(zod_1.z.string()).default([]),
    insumosUsados: zod_1.z
        .array(zod_1.z.object({
        insumoId: zod_1.z.number().int().positive(),
        cantidad: zod_1.z.coerce.number().positive(),
    }))
        .default([]),
});
const FechaDTO = zod_1.z.object({ fecha: zod_1.z.coerce.date() });
const CerrarMultipartDTO = zod_1.z.object({
    observaciones: zod_1.z.string().optional(),
    fechaFinalizarTarea: zod_1.z.string().optional(),
    insumosUsados: zod_1.z.string().optional(),
});
class OperarioService {
    constructor(prisma, operarioId) {
        this.prisma = prisma;
        this.operarioId = operarioId;
    }
    /** Obtiene el límite semanal (horas) desde la Empresa del operario */
    async getLimiteHorasSemana() {
        const op = await this.prisma.operario.findUnique({
            where: { id: this.operarioId.toString() },
            select: { empresa: { select: { limiteHorasSemana: true } } },
        });
        return op?.empresa?.limiteHorasSemana ?? 46;
    }
    /** Asigna una tarea al operario respetando el límite semanal empresarial */
    async asignarTarea(payload) {
        const { tareaId } = TareaIdDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
                fechaInicio: true,
                duracionMinutos: true,
                id: true,
                borrador: true,
            },
        });
        if (!tarea)
            throw new Error("Tarea no encontrada");
        if (tarea.borrador) {
            throw new Error("No se puede asignar una tarea en borrador.");
        }
        const limite = await this.getLimiteHorasSemana();
        const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
        if (horasSemana + tarea.duracionMinutos > limite) {
            const operario = await this.prisma.operario.findUnique({
                where: { id: this.operarioId.toString() },
                include: { usuario: true },
            });
            const nombre = operario?.usuario?.nombre ?? "Operario";
            throw new Error(`❌ Supera el límite de ${limite} horas semanales para ${nombre}`);
        }
        await this.prisma.tarea.update({
            where: { id: tareaId },
            data: { operarios: { connect: { id: this.operarioId.toString() } } },
        });
    }
    /** Inicia una tarea (cambia estado a EN_PROCESO) */
    async iniciarTarea(payload) {
        const { tareaId } = TareaIdDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { id: true, borrador: true },
        });
        if (!tarea || tarea.borrador) {
            throw new Error("La tarea no existe o está en borrador.");
        }
        const tareaService = new TareaServices_1.TareaService(this.prisma, tareaId);
        await tareaService.iniciarTarea();
    }
    /**
     * Marca tarea como completada y consume insumos.
     * - Usa InventarioService para registrar el consumo (con operarioId/tareaId si tu versión lo soporta).
     * - Cambia estado a PENDIENTE_APROBACION (lo hace TareaService).
     * - Actualiza evidencias.
     */
    async marcarComoCompletada(payload, inventarioService) {
        const { tareaId, evidencias, insumosUsados } = MarcarCompletadaDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { id: true, conjuntoId: true, borrador: true },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        if (tarea.borrador) {
            throw new Error("No se puede completar una tarea en borrador.");
        }
        if (tarea.conjuntoId === null) {
            throw new Error("❌ La tarea no tiene un conjunto asignado.");
        }
        // Si tu InventarioService.consumirInsumoPorId acepta metadata (operarioId/tareaId),
        // puedes pasarla así para evitar duplicados y tener mejor trazabilidad.
        // Ej: await inventarioService.consumirInsumoPorId({ insumoId, cantidad, operarioId: this.operarioId, tareaId })
        await new TareaServices_1.TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos({ insumosUsados }, {
            // Adapter que cumple con (payload: unknown) => Promise<void>
            consumirInsumoPorId: async (payload) => {
                // valida/extrae campos con Zod (opcional pero recomendado)
                const p = zod_1.z
                    .object({
                    insumoId: zod_1.z.number().int().positive(),
                    cantidad: zod_1.z.number().int().positive(),
                })
                    .parse(payload);
                // llama a tu InventarioService con el shape que ya acepta
                // si en tu InventarioService agregaste metadata (operarioId/tareaId),
                // complétala aquí.
                await inventarioService.consumirInsumoPorId({
                    insumoId: p.insumoId,
                    cantidad: p.cantidad,
                    // operarioId: this.operarioId,
                    // tareaId,
                });
            },
        });
        // Guardar/mergear evidencias (no lo hace TareaService)
        const actuales = (await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { evidencias: true },
        }))?.evidencias ?? [];
        await this.prisma.tarea.update({
            where: { id: tareaId },
            data: { evidencias: [...actuales, ...evidencias] },
        });
    }
    /** Marca una tarea como NO_COMPLETADA */
    async marcarComoNoCompletada(payload) {
        const { tareaId } = TareaIdDTO.parse(payload);
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { id: true, borrador: true },
        });
        if (!tarea || tarea.borrador) {
            throw new Error("La tarea no existe o está en borrador.");
        }
        const tareaService = new TareaServices_1.TareaService(this.prisma, tareaId);
        await tareaService.marcarNoCompletada();
    }
    /** Tareas del día para este operario */
    async tareasDelDia(payload) {
        const { fecha } = FechaDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                operarios: { some: { id: this.operarioId.toString() } },
                borrador: false,
                fechaInicio: { lte: fecha },
                fechaFin: { gte: fecha },
            },
        });
    }
    async listarTareas() {
        return this.prisma.tarea.findMany({
            where: {
                operarios: { some: { id: this.operarioId.toString() } },
                borrador: false,
            },
            orderBy: { fechaInicio: "asc" },
            include: {
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                conjunto: true,
            },
        });
    }
    async cerrarTareaConEvidencias(tareaId, payload, files) {
        const dto = CerrarMultipartDTO.parse(payload ?? {});
        const fechaCierre = dto.fechaFinalizarTarea
            ? new Date(dto.fechaFinalizarTarea)
            : new Date();
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: {
                id: true,
                descripcion: true,
                estado: true,
                borrador: true,
                evidencias: true,
                conjuntoId: true,
                supervisorId: true,
                operarios: { select: { id: true } },
                conjunto: { select: { nit: true, nombre: true } },
            },
        });
        if (!tarea)
            throw new Error("❌ Tarea no encontrada.");
        if (tarea.borrador) {
            throw new Error("No se puede cerrar una tarea en borrador.");
        }
        const operarioAsignado = tarea.operarios.some((o) => o.id === this.operarioId.toString());
        if (!operarioAsignado) {
            throw new Error("❌ Esta tarea no está asignada al operario autenticado.");
        }
        const permitidos = new Set([
            client_1.EstadoTarea.ASIGNADA,
            client_1.EstadoTarea.EN_PROCESO,
            client_1.EstadoTarea.COMPLETADA,
        ]);
        if (!permitidos.has(tarea.estado)) {
            throw new Error(`No puedes cerrar una tarea en estado ${tarea.estado}.`);
        }
        if (!tarea.conjuntoId) {
            throw new Error("La tarea no tiene conjunto asignado, no puedo descontar inventario.");
        }
        let insumosUsados = [];
        if (dto.insumosUsados && dto.insumosUsados.trim().length) {
            try {
                insumosUsados = zod_1.z
                    .array(zod_1.z.object({
                    insumoId: zod_1.z.number().int().positive(),
                    cantidad: zod_1.z.number().positive(),
                }))
                    .parse(JSON.parse(dto.insumosUsados));
            }
            catch {
                throw new Error("insumosUsados debe ser un JSON válido: [{insumoId, cantidad}]");
            }
        }
        const urls = [];
        try {
            for (const f of files ?? []) {
                const url = await (0, drive_evidencias_1.uploadEvidenciaToDrive)({
                    filePath: f.path,
                    fileName: `Tarea_${tareaId}_${fechaCierre
                        .toISOString()
                        .replace(/[:.]/g, "-")}_${f.originalname}`,
                    mimeType: f.mimetype,
                    conjuntoNit: tarea.conjunto?.nit ?? tarea.conjuntoId,
                    conjuntoNombre: tarea.conjunto?.nombre ?? undefined,
                    fecha: fechaCierre,
                });
                urls.push(url);
            }
        }
        finally {
            for (const f of files ?? []) {
                try {
                    if (fs_1.default.existsSync(f.path))
                        fs_1.default.unlinkSync(f.path);
                }
                catch { }
            }
        }
        const evidenciasMerge = [...(tarea.evidencias ?? []), ...urls];
        await this.prisma.$transaction(async (tx) => {
            const inventario = await tx.inventario.findUnique({
                where: { conjuntoId: tarea.conjuntoId },
                select: { id: true },
            });
            if (!inventario) {
                throw new Error("No existe inventario para este conjunto.");
            }
            for (const item of insumosUsados) {
                const invItem = await tx.inventarioInsumo.findUnique({
                    where: {
                        inventarioId_insumoId: {
                            inventarioId: inventario.id,
                            insumoId: item.insumoId,
                        },
                    },
                    select: { id: true, cantidad: true },
                });
                if (!invItem) {
                    throw new Error(`El insumo ${item.insumoId} no existe en inventario del conjunto.`);
                }
                const actual = invItem.cantidad;
                const usar = new client_1.Prisma.Decimal(item.cantidad);
                if (usar.lte(0))
                    continue;
                if (actual.lt(usar)) {
                    throw new Error(`Stock insuficiente para insumo ${item.insumoId}. Stock=${actual.toString()} / Usar=${usar.toString()}`);
                }
                await tx.inventarioInsumo.update({
                    where: { id: invItem.id },
                    data: { cantidad: actual.minus(usar) },
                });
                await tx.consumoInsumo.create({
                    data: {
                        inventario: { connect: { id: inventario.id } },
                        insumo: { connect: { id: item.insumoId } },
                        tipo: client_1.TipoMovimientoInsumo.SALIDA,
                        tarea: { connect: { id: tareaId } },
                        operario: { connect: { id: this.operarioId.toString() } },
                        cantidad: usar,
                        fecha: fechaCierre,
                        observacion: `Consumo en cierre de tarea #${tareaId} por operario ${this.operarioId}`,
                    },
                });
            }
            await tx.usoMaquinaria.updateMany({
                where: { tareaId, fechaFin: null },
                data: {
                    fechaFin: fechaCierre,
                    operarioId: this.operarioId.toString(),
                    observacion: "Devuelta al cerrar tarea por operario",
                },
            });
            await tx.usoHerramienta.updateMany({
                where: { tareaId, fechaFin: null },
                data: {
                    fechaFin: fechaCierre,
                    operarioId: this.operarioId.toString(),
                    estado: client_1.EstadoUsoHerramienta.DEVUELTA,
                    observacion: "Devuelta al cerrar tarea por operario",
                },
            });
            await tx.maquinariaConjunto.updateMany({
                where: { tareaId },
                data: { tareaId: null, operarioId: null, fechaDevolucionEstimada: null },
            });
            await tx.tarea.update({
                where: { id: tareaId },
                data: {
                    evidencias: evidenciasMerge,
                    observaciones: dto.observaciones ?? undefined,
                    insumosUsados: insumosUsados,
                    estado: client_1.EstadoTarea.PENDIENTE_APROBACION,
                    fechaFinalizarTarea: fechaCierre,
                    finalizadaPorId: this.operarioId.toString(),
                    finalizadaPorRol: "OPERARIO",
                },
            });
        });
        try {
            const notificaciones = new NotificacionService_1.NotificacionService(this.prisma);
            await notificaciones.notificarCierreTarea({
                tareaId,
                descripcionTarea: tarea.descripcion,
                conjuntoId: tarea.conjuntoId,
                actorId: this.operarioId.toString(),
                actorRol: "OPERARIO",
                supervisorId: tarea.supervisorId,
            });
        }
        catch (e) {
            console.error("No se pudo notificar cierre de tarea (operario):", e);
        }
    }
    /** Suma de horas en la semana (lunes a domingo) de la fecha dada */
    async horasAsignadasEnSemana(fecha) {
        const inicio = this.inicioSemana(fecha);
        const fin = new Date(inicio);
        fin.setDate(inicio.getDate() + 6);
        fin.setHours(23, 59, 59, 999);
        const tareas = await this.prisma.tarea.findMany({
            where: {
                operarios: { some: { id: this.operarioId.toString() } },
                borrador: false,
                fechaFin: { gte: inicio },
                fechaInicio: { lte: fin },
            },
            select: { duracionMinutos: true },
        });
        return tareas.reduce((sum, t) => sum + t.duracionMinutos, 0);
    }
    async horasRestantesEnSemana(payload) {
        const { fecha } = FechaDTO.parse(payload);
        const limite = await this.getLimiteHorasSemana();
        const horas = await this.horasAsignadasEnSemana(fecha);
        return Math.max(0, limite - horas);
    }
    async resumenDeHoras(payload) {
        const { fecha } = FechaDTO.parse(payload);
        const limite = await this.getLimiteHorasSemana();
        const horas = await this.horasAsignadasEnSemana(fecha);
        const operario = await this.prisma.operario.findUnique({
            where: { id: this.operarioId.toString() },
            include: { usuario: true },
        });
        const nombre = operario?.usuario?.nombre ?? "Operario";
        return `🔔 A ${nombre} le quedan ${Math.max(0, limite - horas)}h disponibles esta semana (límite ${limite}h).`;
        // si quieres, puedes retornar también { horasAsignadas: horas, limite, restantes: limite - horas }
    }
    /** Lunes de la semana ISO de la fecha dada */
    inicioSemana(fecha) {
        const d = new Date(fecha);
        const day = d.getDay(); // 0=Dom ... 6=Sab
        const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Lunes
        return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
    }
}
exports.OperarioService = OperarioService;
