"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TareaService = void 0;
// src/services/TareaService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const Tarea_1 = require("../model/Tarea");
const schedulerUtils_1 = require("../utils/schedulerUtils");
const EvidenciaDTO = zod_1.z.object({ imagen: zod_1.z.string().min(1) });
const ConsumoItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
const CompletarConInsumosDTO = zod_1.z.object({
    insumosUsados: zod_1.z.array(ConsumoItemDTO).default([]),
});
const SupervisorIdDTO = zod_1.z.object({ supervisorId: zod_1.z.number().int().positive() });
const RechazarDTO = zod_1.z.object({
    supervisorId: zod_1.z.number().int().positive(),
    observacion: zod_1.z.string().min(3).max(500),
});
class TareaService {
    constructor(prisma, tareaId) {
        this.prisma = prisma;
        this.tareaId = tareaId;
    }
    /* =====================================================
     *       CRUD GENERAL (CORRECTIVAS POR DEFECTO)
     * ===================================================== */
    // ✅ Crear tarea (correctiva por defecto)
    async iniciarTarea() {
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: this.tareaId },
            select: { estado: true },
        });
        if (!tarea)
            throw new Error("Tarea no encontrada.");
        if (tarea.estado !== client_1.EstadoTarea.ASIGNADA) {
            throw new Error("Solo se puede iniciar una tarea que esté ASIGNADA.");
        }
        await this.prisma.tarea.update({
            where: { id: this.tareaId },
            data: {
                estado: client_1.EstadoTarea.EN_PROCESO,
                fechaIniciarTarea: new Date(),
            },
        });
    }
    async marcarComoCompletadaConInsumos(payload, inventarioService) {
        const { insumosUsados } = CompletarConInsumosDTO.parse(payload);
        await this.prisma.$transaction(async () => {
            // 1) Consumir insumos (si falla, aborta la transacción)
            for (const { insumoId, cantidad } of insumosUsados) {
                await inventarioService.consumirInsumoPorId({ insumoId, cantidad });
            }
            // 2) Cambiar estado -> PENDIENTE_APROBACION y guardar snapshot de insumosUsados
            await this.prisma.tarea.update({
                where: { id: this.tareaId },
                data: {
                    insumosUsados, // Json
                    estado: client_1.EstadoTarea.PENDIENTE_APROBACION,
                    fechaFinalizarTarea: new Date(),
                },
            });
        });
    }
    async marcarNoCompletada() {
        await this.prisma.tarea.update({
            where: { id: this.tareaId },
            data: { estado: client_1.EstadoTarea.NO_COMPLETADA },
        });
    }
    static async crearTareaCorrectiva(prisma, payload) {
        const dto = Tarea_1.CrearTareaDTO.parse(payload);
        const esDomingo = dto.fechaInicio.getDay() === 0;
        const esFestivo = await (0, schedulerUtils_1.isFestivoDate)({
            prisma,
            fecha: dto.fechaInicio,
            pais: "CO",
        });
        if (esDomingo || esFestivo) {
            throw new Error("No se permite programar tareas en domingos o festivos.");
        }
        // Operarios (M:N)
        const operariosConnect = dto.operariosIds && dto.operariosIds.length
            ? dto.operariosIds.map((id) => ({ id: id }))
            : dto.operarioId
                ? [{ id: dto.operarioId }]
                : [];
        const data = {
            descripcion: dto.descripcion,
            fechaInicio: dto.fechaInicio,
            fechaFin: dto.fechaFin,
            duracionMinutos: dto.duracionMinutos,
            tipo: dto.tipo ?? client_1.TipoTarea.CORRECTIVA,
            estado: dto.estado ?? client_1.EstadoTarea.ASIGNADA,
            frecuencia: dto.frecuencia ?? null,
            evidencias: dto.evidencias ?? [],
            insumosUsados: dto.insumosUsados ?? undefined,
            observaciones: dto.observaciones ?? null,
            observacionesRechazo: dto.observacionesRechazo ?? null,
            ubicacion: { connect: { id: dto.ubicacionId } },
            elemento: { connect: { id: dto.elementoId } },
        };
        // Conjunto (por NIT)
        if (dto.conjuntoId) {
            data.conjunto = { connect: { nit: dto.conjuntoId } };
        }
        // Supervisor (id numérico → string)
        if (dto.supervisorId != null) {
            data.supervisor = { connect: { id: dto.supervisorId } };
        }
        // Operarios
        if (operariosConnect.length) {
            data.operarios = { connect: operariosConnect };
        }
        const creada = await prisma.tarea.create({
            data,
            select: Tarea_1.tareaPublicSelect,
        });
        return (0, Tarea_1.toTareaPublica)(creada);
    }
    // ✏️ Editar tarea
    static async editarTarea(prisma, id, payload) {
        const dto = Tarea_1.EditarTareaDTO.parse(payload);
        const data = {
            descripcion: dto.descripcion ?? undefined,
            fechaInicio: dto.fechaInicio ?? undefined,
            fechaFin: dto.fechaFin ?? undefined,
            duracionHoras: dto.duracionHoras ?? undefined,
            tipo: dto.tipo ?? undefined,
            estado: dto.estado ?? undefined,
            frecuencia: dto.frecuencia ?? undefined,
            evidencias: dto.evidencias ?? undefined,
            insumosUsados: dto.insumosUsados ?? undefined,
            observaciones: dto.observaciones !== undefined ? dto.observaciones : undefined,
            observacionesRechazo: dto.observacionesRechazo !== undefined
                ? dto.observacionesRechazo
                : undefined,
        };
        if (dto.ubicacionId != null) {
            data.ubicacion = { connect: { id: dto.ubicacionId } };
        }
        if (dto.elementoId != null) {
            data.elemento = { connect: { id: dto.elementoId } };
        }
        if (dto.conjuntoId !== undefined) {
            data.conjunto = dto.conjuntoId
                ? { connect: { nit: dto.conjuntoId } }
                : { disconnect: true };
        }
        if (dto.supervisorId !== undefined) {
            data.supervisor =
                dto.supervisorId != null
                    ? { connect: { id: dto.supervisorId } }
                    : { disconnect: true };
        }
        // Reemplazar operarios si viene el array
        if (dto.operariosIds) {
            data.operarios = {
                set: dto.operariosIds.map((id) => ({ id: id })),
            };
        }
        const actualizada = await prisma.tarea.update({
            where: { id },
            data,
            select: Tarea_1.tareaPublicSelect,
        });
        return (0, Tarea_1.toTareaPublica)(actualizada);
    }
    // 🔍 Obtener una tarea
    static async obtenerTarea(prisma, id) {
        const tarea = await prisma.tarea.findUnique({
            where: { id },
            select: Tarea_1.tareaPublicSelect,
        });
        if (!tarea)
            throw new Error("Tarea no encontrada.");
        return (0, Tarea_1.toTareaPublica)(tarea);
    }
    // 📋 Listar tareas con filtros
    static async listarTareas(prisma, payloadFiltro) {
        const filtro = payloadFiltro ? Tarea_1.FiltroTareaDTO.parse(payloadFiltro) : {};
        const where = {};
        if (filtro.conjuntoId)
            where.conjuntoId = filtro.conjuntoId;
        if (filtro.ubicacionId)
            where.ubicacionId = filtro.ubicacionId;
        if (filtro.elementoId)
            where.elementoId = filtro.elementoId;
        if (filtro.operarioId) {
            where.operarios = {
                some: { id: filtro.operarioId },
            };
        }
        if (filtro.supervisorId) {
            where.supervisorId = filtro.supervisorId;
        }
        if (filtro.tipo)
            where.tipo = filtro.tipo;
        if (filtro.frecuencia)
            where.frecuencia = filtro.frecuencia;
        if (filtro.estado)
            where.estado = filtro.estado;
        if (filtro.borrador !== undefined)
            where.borrador = filtro.borrador;
        if (filtro.periodoAnio)
            where.periodoAnio = filtro.periodoAnio;
        if (filtro.periodoMes)
            where.periodoMes = filtro.periodoMes;
        if (filtro.grupoPlanId)
            where.grupoPlanId = filtro.grupoPlanId;
        if (filtro.fechaInicio || filtro.fechaFin) {
            where.fechaInicio = {};
            if (filtro.fechaInicio)
                where.fechaInicio.gte = filtro.fechaInicio;
            if (filtro.fechaFin)
                where.fechaInicio.lte = filtro.fechaFin;
        }
        const tareas = await prisma.tarea.findMany({
            where,
            select: Tarea_1.tareaPublicSelect,
            orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
        });
        return tareas.map(Tarea_1.toTareaPublica);
    }
    // 🗑️ Eliminar tarea (con regla de negocio)
    static async eliminarTarea(prisma, id) {
        const tarea = await prisma.tarea.findUnique({
            where: { id },
            select: {
                id: true,
                estado: true,
                borrador: true,
            },
        });
        if (!tarea)
            throw new Error("Tarea no encontrada.");
        // 🔒 Reglas de negocio (ajústalas a tu gusto)
        if (tarea.estado === client_1.EstadoTarea.COMPLETADA ||
            tarea.estado === client_1.EstadoTarea.APROBADA ||
            tarea.estado === client_1.EstadoTarea.PENDIENTE_APROBACION) {
            throw new Error("No se puede eliminar una tarea que ya fue ejecutada o está en aprobación.");
        }
        // ✅ Recomendación: si NO es borrador, mejor CANCELAR en vez de borrar
        // (si quieres permitir borrado igual, comenta este bloque)
        if (!tarea.borrador) {
            throw new Error("No se permite eliminar tareas publicadas. Cáncelala (estado CANCELADA) o elimine solo borradores.");
        }
        await prisma.$transaction(async (tx) => {
            // 1) Liberar maquinaria asignada al conjunto por esta tarea (si existiera)
            // (tu relación tiene onDelete: SetNull, pero igual lo hacemos explícito)
            await tx.maquinariaConjunto.updateMany({
                where: { tareaId: id },
                data: { tareaId: null },
            });
            const [um, uh, ci, mc] = await Promise.all([
                prisma.usoMaquinaria.count({ where: { tarea } }),
                prisma.usoHerramienta.count({ where: { tarea } }),
                prisma.consumoInsumo.count({ where: { tarea } }),
                prisma.maquinariaConjunto.count({ where: { tarea } }),
            ]);
            console.log("refs tarea", { um, uh, ci, mc });
            // 2) Borrar usos de maquinaria/herramienta ligados a la tarea (FK dura)
            await tx.usoMaquinaria.deleteMany({
                where: { tareaId: id },
            });
            await tx.usoHerramienta.deleteMany({
                where: { tareaId: id },
            });
            // 3) Borrar consumos ligados a la tarea (si aplica en tu schema real)
            await tx.consumoInsumo.deleteMany({
                where: { tareaId: id },
            });
            // 4) (Opcional) Desconectar relación M:N de operarios (normalmente Prisma lo limpia,
            // pero lo dejo por si tu DB tiene restricciones raras)
            await tx.tarea.update({
                where: { id },
                data: { operarios: { set: [] } },
            });
            // 5) Ahora sí, borrar la tarea
            await tx.tarea.delete({ where: { id } });
        });
        return { ok: true, message: "Tarea eliminada correctamente." };
    }
}
exports.TareaService = TareaService;
