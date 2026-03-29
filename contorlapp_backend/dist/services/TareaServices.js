"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TareaService = void 0;
// src/services/TareaService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const Tarea_1 = require("../model/Tarea");
const schedulerUtils_1 = require("../utils/schedulerUtils");
const operarioAvailability_1 = require("../utils/operarioAvailability");
const EvidenciaDTO = zod_1.z.object({ imagen: zod_1.z.string().min(1) });
const ConsumoItemDTO = zod_1.z.object({
    insumoId: zod_1.z.number().int().positive(),
    cantidad: zod_1.z.number().int().positive(),
});
async function validarOperariosEnHorarioTarea(params) {
    const { prisma, conjuntoId, fechaInicio, fechaFin, operariosIds } = params;
    if (!conjuntoId || !operariosIds.length)
        return;
    const toMin = (value) => {
        const text = String(value ?? "").trim();
        const match = text.match(/(\d{1,2}):(\d{2})/);
        if (!match)
            return null;
        return Number(match[1]) * 60 + Number(match[2]);
    };
    const dia = fechaInicio.getDay();
    const horarios = await prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
    const horario = horarios.find((h) => {
        const map = {
            LUNES: 1,
            MARTES: 2,
            MIERCOLES: 3,
            JUEVES: 4,
            VIERNES: 5,
            SABADO: 6,
            DOMINGO: 0,
        };
        return map[String(h.dia)] === dia;
    });
    if (!horario)
        return;
    const jornadas = await prisma.operario.findMany({
        where: { id: { in: operariosIds } },
        select: {
            id: true,
            usuario: { select: { jornadaLaboral: true, patronJornada: true } },
        },
    });
    const jornadasByOperario = new Map(jornadas.map((j) => [
        j.id,
        {
            jornadaLaboral: j.usuario?.jornadaLaboral ?? null,
            patronJornada: j.usuario?.patronJornada ?? null,
        },
    ]));
    const startMin = toMin(horario.horaApertura);
    const endMin = toMin(horario.horaCierre);
    if (startMin == null || endMin == null)
        return;
    const result = await (0, operarioAvailability_1.validarOperariosDisponiblesEnRango)({
        prisma,
        fechaInicio,
        fechaFin,
        operariosIds,
        jornadasByOperario,
        horarioDia: {
            startMin,
            endMin,
            descansoStartMin: horario.descansoInicio
                ? toMin(horario.descansoInicio) ?? undefined
                : undefined,
            descansoEndMin: horario.descansoFin
                ? toMin(horario.descansoFin) ?? undefined
                : undefined,
        },
    });
    if (!result.ok) {
        throw new Error(`Los operarios ${result.noDisponibles.join(", ")} no tienen horario disponible para ese rango.`);
    }
}
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
        const esFestivo = await (0, schedulerUtils_1.isFestivoDate)({
            prisma,
            fecha: dto.fechaInicio,
            pais: "CO",
        });
        if (esFestivo) {
            throw new Error("No se permite programar tareas en festivos.");
        }
        const operarios = dto.operariosIds?.length
            ? dto.operariosIds.map(String)
            : dto.operarioId
                ? [String(dto.operarioId)]
                : [];
        if (operarios.length) {
            const disponibilidad = await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
                prisma,
                fecha: dto.fechaInicio,
                operariosIds: operarios,
            });
            if (!disponibilidad.ok) {
                throw new Error(`Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`);
            }
            await validarOperariosEnHorarioTarea({
                prisma,
                conjuntoId: dto.conjuntoId ?? null,
                fechaInicio: dto.fechaInicio,
                fechaFin: dto.fechaFin ?? new Date(dto.fechaInicio.getTime() + (dto.duracionMinutos ?? Math.round((dto.duracionHoras ?? 1) * 60)) * 60000),
                operariosIds: operarios,
            });
            if (dto.conjuntoId) {
                const duracionMinutos = dto.duracionMinutos ??
                    (dto.fechaFin
                        ? Math.max(1, Math.round((dto.fechaFin.getTime() - dto.fechaInicio.getTime()) / 60000))
                        : Math.max(1, Math.round((dto.duracionHoras ?? 1) * 60)));
                const limite = await (0, operarioAvailability_1.validarLimiteSemanalOperarios)({
                    prisma,
                    conjuntoId: dto.conjuntoId,
                    operariosIds: operarios,
                    fechaInicio: dto.fechaInicio,
                    duracionMinutos,
                });
                if (!limite.ok) {
                    throw new Error(`Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta tarea.`);
                }
            }
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
        const actual = await prisma.tarea.findUnique({
            where: { id },
            select: {
                conjuntoId: true,
                fechaInicio: true,
                fechaFin: true,
                operarios: { select: { id: true } },
            },
        });
        const fechaInicioFinal = dto.fechaInicio ?? actual?.fechaInicio;
        const fechaFinFinal = dto.fechaFin ?? actual?.fechaFin;
        const conjuntoIdFinal = dto.conjuntoId !== undefined ? dto.conjuntoId : actual?.conjuntoId;
        const operariosFinal = dto.operariosIds?.map(String) ?? actual?.operarios.map((o) => o.id) ?? [];
        if (fechaInicioFinal && fechaFinFinal && operariosFinal.length) {
            const disponibilidad = await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
                prisma,
                fecha: fechaInicioFinal,
                operariosIds: operariosFinal,
            });
            if (!disponibilidad.ok) {
                throw new Error(`Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`);
            }
            await validarOperariosEnHorarioTarea({
                prisma,
                conjuntoId: conjuntoIdFinal ?? null,
                fechaInicio: fechaInicioFinal,
                fechaFin: fechaFinFinal,
                operariosIds: operariosFinal,
            });
            if (conjuntoIdFinal) {
                const duracionMinutos = Math.max(1, Math.round((fechaFinFinal.getTime() - fechaInicioFinal.getTime()) / 60000));
                const limite = await (0, operarioAvailability_1.validarLimiteSemanalOperarios)({
                    prisma,
                    conjuntoId: conjuntoIdFinal,
                    operariosIds: operariosFinal,
                    fechaInicio: fechaInicioFinal,
                    duracionMinutos,
                    excluirTareaId: id,
                });
                if (!limite.ok) {
                    throw new Error(`Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta tarea.`);
                }
            }
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
