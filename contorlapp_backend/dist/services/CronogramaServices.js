"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CronogramaService = void 0;
// src/services/CronogramaService.ts
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const schedulerUtils_1 = require("../utils/schedulerUtils");
const elementoHierarchy_1 = require("../utils/elementoHierarchy");
const operarioAvailability_1 = require("../utils/operarioAvailability");
// DTOs locales de filtros para este servicio
const OperarioIdDTO = zod_1.z.object({ operarioId: zod_1.z.number().int().positive() });
const FechaDTO = zod_1.z.object({ fecha: zod_1.z.coerce.date() });
const RangoFechasDTO = zod_1.z
    .object({
    fechaInicio: zod_1.z.coerce.date(),
    fechaFin: zod_1.z.coerce.date(),
})
    .refine((d) => d.fechaFin >= d.fechaInicio, {
    message: "fechaFin debe ser mayor o igual a fechaInicio",
    path: ["fechaFin"],
});
const CronoMesDTO = zod_1.z.object({
    anio: zod_1.z.number().int().min(2000).max(2100),
    mes: zod_1.z.number().int().min(1).max(12),
    borrador: zod_1.z.boolean().optional(), // undefined = todos, true = solo borrador, false = solo operativo
});
const SugerirDTO = zod_1.z.object({
    fechaInicio: zod_1.z.coerce.date(),
    fechaFin: zod_1.z.coerce.date(),
    max: zod_1.z.number().int().min(1).max(20).optional().default(5),
    requiereFuncion: zod_1.z.string().optional(),
});
const TareasPorFiltroDTO = zod_1.z
    .object({
    operarioId: zod_1.z.number().int().positive().optional(),
    fechaExacta: zod_1.z.coerce.date().optional(),
    fechaInicio: zod_1.z.coerce.date().optional(),
    fechaFin: zod_1.z.coerce.date().optional(),
    ubicacion: zod_1.z.string().optional(),
})
    .refine((d) => {
    if (d.fechaExacta)
        return true;
    return ((!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin)));
}, { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." });
const ESTADOS_NO_CRONOGRAMA = ["PENDIENTE_REPROGRAMACION"];
/** Util: sumar minutos a una fecha (sin mutar la original) */
function addMinutes(d, minutes) {
    return new Date(d.getTime() + minutes * 60 * 1000);
}
/** Util: devuelve el lunes de la semana de una fecha (semana ISO) */
function mondayOfWeek(d) {
    const day = d.getDay(); // 0 dom - 6 sab
    const diff = d.getDate() - day + (day === 0 ? -6 : 1);
    return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}
/** Util: simple chequeo de solapamiento de intervalos [a,b] con [c,d] (inclusive) */
function overlap(aStart, aEnd, bStart, bEnd) {
    return aStart <= bEnd && bStart <= aEnd;
}
const WEEKDAY_NAMES_ES = [
    "domingo",
    "lunes",
    "martes",
    "miercoles",
    "jueves",
    "viernes",
    "sabado",
];
function dateKeyLocal(d) {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, "0");
    const day = String(d.getDate()).padStart(2, "0");
    return `${y}-${m}-${day}`;
}
class CronogramaService {
    constructor(prisma, conjuntoId) {
        this.prisma = prisma;
        this.conjuntoId = conjuntoId;
    }
    async eliminarTareaPublicada(id) {
        await this.prisma.$transaction(async (tx) => {
            await tx.maquinariaConjunto.updateMany({
                where: { tareaId: id },
                data: { tareaId: null },
            });
            await tx.usoMaquinaria.deleteMany({ where: { tareaId: id } });
            await tx.usoHerramienta.deleteMany({ where: { tareaId: id } });
            await tx.consumoInsumo.deleteMany({ where: { tareaId: id } });
            await tx.tarea.update({
                where: { id },
                data: { operarios: { set: [] } },
            });
            await tx.tarea.delete({ where: { id } });
        });
    }
    /* ==================== Consultas básicas ==================== */
    async cronogramaMensual(payload) {
        const { anio, mes, borrador } = CronoMesDTO.parse(payload);
        // Rango del mes
        const inicioMes = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
        const finMes = new Date(anio, mes, 0, 23, 59, 59, 999); // último día del mes
        const where = {
            conjuntoId: this.conjuntoId,
            estado: { notIn: ESTADOS_NO_CRONOGRAMA },
            fechaFin: { gte: inicioMes },
            fechaInicio: { lte: finMes },
        };
        if (borrador !== undefined) {
            where.borrador = borrador;
        }
        return this.prisma.tarea.findMany({
            where,
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    async eliminarCronogramaPublicado() {
        const tareas = await this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
            },
            select: { id: true, estado: true },
            orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
        });
        if (!tareas.length) {
            return { ok: true, eliminadas: 0 };
        }
        const tareasBloqueadas = tareas.filter((tarea) => tarea.estado === client_1.EstadoTarea.COMPLETADA ||
            tarea.estado === client_1.EstadoTarea.PENDIENTE_APROBACION);
        if (tareasBloqueadas.length > 0) {
            throw new Error("No se puede eliminar el cronograma porque tiene tareas completadas o pendientes de aprobacion.");
        }
        const tareaIds = tareas.map((tarea) => tarea.id);
        for (const tareaId of tareaIds) {
            await this.eliminarTareaPublicada(tareaId);
        }
        const restantes = await this.prisma.tarea.count({
            where: { id: { in: tareaIds } },
        });
        const eliminadas = tareaIds.length - restantes;
        if (restantes > 0) {
            throw new Error("No se pudo eliminar completamente el cronograma publicado.");
        }
        return { ok: true, eliminadas };
    }
    async tareasPorOperario(payload) {
        const { operarioId } = OperarioIdDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                operarios: { some: { id: operarioId.toString() } },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    async tareasPorFecha(payload) {
        const { fecha } = FechaDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                fechaInicio: { lte: fecha },
                fechaFin: { gte: fecha },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    async tareasEnRango(payload) {
        const { fechaInicio, fechaFin } = RangoFechasDTO.parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                // solape de rangos
                fechaFin: { gte: fechaInicio },
                fechaInicio: { lte: fechaFin },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    async tareasPorUbicacion(payload) {
        const { ubicacion } = zod_1.z
            .object({ ubicacion: zod_1.z.string().min(1) })
            .parse(payload);
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                // según tu versión de Prisma, podrías necesitar { is: { nombre: ... } }
                ubicacion: { nombre: { equals: ubicacion, mode: "insensitive" } },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    async tareasPorFiltro(payload) {
        const f = TareasPorFiltroDTO.parse(payload);
        // Si llega fechaExacta, interpretamos el día completo
        let fechaInicio;
        let fechaFin;
        if (f.fechaExacta) {
            const d0 = new Date(f.fechaExacta);
            fechaInicio = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate(), 0, 0, 0, 0);
            fechaFin = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate(), 23, 59, 59, 999);
        }
        else {
            fechaInicio = f.fechaInicio ?? undefined;
            fechaFin = f.fechaFin ?? undefined;
        }
        return this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                borrador: false,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                operarios: f.operarioId
                    ? { some: { id: f.operarioId.toString() } }
                    : undefined,
                fechaInicio: fechaFin ? { lte: fechaFin } : undefined,
                fechaFin: fechaInicio ? { gte: fechaInicio } : undefined,
                ubicacion: f.ubicacion
                    ? { nombre: { equals: f.ubicacion, mode: "insensitive" } }
                    : undefined,
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
    }
    /* ==================== Calendario / UI por bloques ==================== */
    /**
     * Vista diaria agrupada por franjas (por defecto 60 min).
     * Devuelve array de:
     *  { inicio: Date, fin: Date, tareas: [{ id, descripcion, operarios: [{id, nombre}], ubicacion, elemento, ... }] }
     */
    async vistaDiariaPorHoras(payload, pasoMinutos = 60) {
        const { fecha } = FechaDTO.parse(payload);
        const inicioDia = new Date(fecha);
        inicioDia.setHours(0, 0, 0, 0);
        const finDia = new Date(fecha);
        finDia.setHours(23, 59, 59, 999);
        // Trae todas las tareas que toquen el día
        const tareas = await this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                fechaFin: { gte: inicioDia },
                fechaInicio: { lte: finDia },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: { fechaInicio: "asc" },
        });
        // Creamos las franjas
        const slots = [];
        let cursor = new Date(inicioDia);
        while (cursor <= finDia) {
            const slotInicio = new Date(cursor);
            const slotFin = addMinutes(slotInicio, pasoMinutos);
            slots.push({ inicio: slotInicio, fin: slotFin, tareas: [] });
            cursor = slotFin;
        }
        // Asignamos tareas a franjas si se solapan
        for (const t of tareas) {
            for (const s of slots) {
                if (overlap(t.fechaInicio, t.fechaFin, s.inicio, s.fin)) {
                    s.tareas.push({
                        id: t.id,
                        descripcion: t.descripcion,
                        operarios: t.operarios.map((o) => ({
                            id: o.id,
                            nombre: o.usuario?.nombre ?? null,
                        })),
                        ubicacion: t.ubicacion?.nombre ?? null,
                        elemento: (0, elementoHierarchy_1.construirRutaElemento)(t.elemento) ?? null,
                        desde: t.fechaInicio,
                        hasta: t.fechaFin,
                    });
                }
            }
        }
        return slots;
    }
    /**
     * Vista semanal por franjas (lunes a domingo).
     * `inicioSemanaISO`: fecha dentro de la semana deseada (cualquier día). Se normaliza a lunes.
     */
    async vistaSemanalPorHoras(inicioSemanaISO, pasoMinutos = 60) {
        const lunes = mondayOfWeek(inicioSemanaISO);
        const domingo = new Date(lunes);
        domingo.setDate(lunes.getDate() + 6);
        domingo.setHours(23, 59, 59, 999);
        const tareas = await this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                fechaFin: { gte: lunes },
                fechaInicio: { lte: domingo },
            },
            include: {
                operarios: { include: { usuario: true } },
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
        // Creamos días -> franjas
        const dias = {};
        for (let d = 0; d < 7; d++) {
            const dia = new Date(lunes);
            dia.setDate(lunes.getDate() + d);
            dia.setHours(0, 0, 0, 0);
            const finDia = new Date(dia);
            finDia.setHours(23, 59, 59, 999);
            const slots = [];
            let cursor = new Date(dia);
            while (cursor <= finDia) {
                const slotInicio = new Date(cursor);
                const slotFin = addMinutes(slotInicio, pasoMinutos);
                slots.push({ inicio: slotInicio, fin: slotFin, tareas: [] });
                cursor = slotFin;
            }
            dias[dia.toISOString().slice(0, 10)] = slots; // clave por YYYY-MM-DD
        }
        // Poblamos por solapamiento
        for (const t of tareas) {
            for (const key of Object.keys(dias)) {
                const slots = dias[key];
                for (const s of slots) {
                    if (overlap(t.fechaInicio, t.fechaFin, s.inicio, s.fin)) {
                        s.tareas.push({
                            id: t.id,
                            descripcion: t.descripcion,
                            operarios: t.operarios.map((o) => ({
                                id: o.id,
                                nombre: o.usuario?.nombre ?? null,
                            })),
                            ubicacion: t.ubicacion?.nombre ?? null,
                            elemento: (0, elementoHierarchy_1.construirRutaElemento)(t.elemento) ?? null,
                            desde: t.fechaInicio,
                            hasta: t.fechaFin,
                        });
                    }
                }
            }
        }
        return dias;
    }
    async sugerirOperarios(payload) {
        const { fechaInicio, fechaFin, max, requiereFuncion } = SugerirDTO.parse(payload);
        // 1) Traer operarios del conjunto
        const operarios = await this.prisma.operario.findMany({
            where: {
                conjuntos: { some: { nit: this.conjuntoId } },
                ...(requiereFuncion
                    ? { funciones: { has: requiereFuncion } }
                    : {}),
            },
            include: { usuario: true },
        });
        if (operarios.length === 0)
            return [];
        // 2) Calcular horas ya asignadas
        const out = [];
        for (const op of operarios) {
            const lunes = mondayOfWeek(fechaInicio);
            const domingo = new Date(lunes);
            domingo.setDate(lunes.getDate() + 6);
            const tareasSemana = await this.prisma.tarea.findMany({
                where: {
                    conjuntoId: this.conjuntoId,
                    operarios: { some: { id: op.id } }, // op.id es string
                    fechaFin: { gte: lunes },
                    fechaInicio: { lte: domingo },
                },
                select: { fechaInicio: true, fechaFin: true, duracionMinutos: true },
            });
            const horas = tareasSemana.reduce((acc, t) => acc + (t.duracionMinutos ?? 0), 0);
            const solapa = tareasSemana.some((t) => t.fechaInicio <= fechaFin && fechaInicio <= t.fechaFin);
            out.push({
                id: op.id, // ya es string, no hace falta toString()
                nombre: op.usuario.nombre,
                horasSemana: horas,
                solapa,
            });
        }
        // 3) Ranking
        out.sort((a, b) => {
            if (a.solapa !== b.solapa)
                return a.solapa ? 1 : -1;
            return a.horasSemana - b.horasSemana;
        });
        return out.slice(0, max);
    }
    async calendarioMensual(params) {
        const { anio, mes, operarioId, tipo, borrador } = params;
        const start = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
        const end = new Date(anio, mes, 0, 23, 59, 59, 999); // último día del mes
        const where = {
            conjuntoId: this.conjuntoId,
            estado: { notIn: ESTADOS_NO_CRONOGRAMA },
            fechaFin: { gte: start },
            fechaInicio: { lte: end },
        };
        if (operarioId)
            where.operarios = { some: { id: operarioId } };
        if (borrador !== undefined)
            where.borrador = borrador;
        if (tipo && tipo !== "TODAS")
            where.tipo = tipo;
        const tareas = await this.prisma.tarea.findMany({
            where,
            select: { fechaInicio: true, fechaFin: true, tipo: true },
        });
        // bucket por día (1..31)
        const daysInMonth = new Date(anio, mes, 0).getDate();
        const dias = Array.from({ length: daysInMonth }, (_, i) => {
            const fecha = new Date(anio, mes - 1, i + 1);
            return {
                dia: i + 1,
                fecha: dateKeyLocal(fecha),
                nombreDia: WEEKDAY_NAMES_ES[fecha.getDay()],
                total: 0,
                preventivas: 0,
                correctivas: 0,
            };
        });
        for (const t of tareas) {
            // marca todos los días que toca (por si cruza)
            const cur = new Date(Math.max(+t.fechaInicio, +start));
            cur.setHours(0, 0, 0, 0);
            const last = new Date(Math.min(+t.fechaFin, +end));
            last.setHours(0, 0, 0, 0);
            while (cur <= last) {
                const d = cur.getDate();
                const slot = dias[d - 1];
                slot.total++;
                if (t.tipo === "PREVENTIVA")
                    slot.preventivas++;
                else
                    slot.correctivas++;
                cur.setDate(cur.getDate() + 1);
            }
        }
        const totalesMes = {
            total: dias.reduce((a, d) => a + d.total, 0),
            preventivas: dias.reduce((a, d) => a + d.preventivas, 0),
            correctivas: dias.reduce((a, d) => a + d.correctivas, 0),
        };
        return { anio, mes, dias, totalesMes };
    }
    /* ==================== Choques y utilidades ==================== */
    /** Devuelve las tareas del operario que se pisan entre sí dentro del rango dado (M:N) */
    async detectarChoques(payload) {
        const { operarioId, fechaInicio, fechaFin } = zod_1.z
            .object({
            operarioId: zod_1.z.number().int().positive(),
            fechaInicio: zod_1.z.coerce.date(),
            fechaFin: zod_1.z.coerce.date(),
        })
            .parse(payload);
        const tareas = await this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
                operarios: { some: { id: operarioId.toString() } },
                fechaFin: { gte: fechaInicio },
                fechaInicio: { lte: fechaFin },
            },
            orderBy: [{ fechaInicio: "asc" }],
        });
        const choques = [];
        for (let i = 0; i < tareas.length; i++) {
            for (let j = i + 1; j < tareas.length; j++) {
                if (overlap(tareas[i].fechaInicio, tareas[i].fechaFin, tareas[j].fechaInicio, tareas[j].fechaFin)) {
                    choques.push({ aId: tareas[i].id, bId: tareas[j].id });
                }
            }
        }
        return choques;
    }
    /** Reprograma fechas de una tarea (sin tocar operarios/ubicación/elemento) */
    async reprogramarTarea(payload) {
        const { tareaId, fechaInicio, fechaFin } = zod_1.z
            .object({
            tareaId: zod_1.z.number().int().positive(),
            fechaInicio: zod_1.z.coerce.date(),
            fechaFin: zod_1.z.coerce.date(),
        })
            .refine((d) => d.fechaFin >= d.fechaInicio, {
            message: "fechaFin debe ser >= fechaInicio",
        })
            .parse(payload);
        const esFestivo = await (0, schedulerUtils_1.isFestivoDate)({
            prisma: this.prisma,
            fecha: fechaInicio,
            pais: "CO",
        });
        if (esFestivo) {
            throw new Error("No se permite reprogramar tareas a festivos.");
        }
        const tarea = await this.prisma.tarea.findUnique({
            where: { id: tareaId },
            select: { operarios: { select: { id: true } } },
        });
        const operariosIds = tarea?.operarios.map((o) => o.id) ?? [];
        if (operariosIds.length) {
            const disponibilidad = await (0, operarioAvailability_1.validarOperariosDisponiblesEnFecha)({
                prisma: this.prisma,
                fecha: fechaInicio,
                operariosIds,
            });
            if (!disponibilidad.ok) {
                throw new Error(`Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`);
            }
            const duracionMinutos = Math.max(1, Math.round((fechaFin.getTime() - fechaInicio.getTime()) / 60000));
            const limite = await (0, operarioAvailability_1.validarLimiteSemanalOperarios)({
                prisma: this.prisma,
                conjuntoId: this.conjuntoId,
                operariosIds,
                fechaInicio,
                duracionMinutos,
                excluirTareaId: tareaId,
            });
            if (!limite.ok) {
                throw new Error(`Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta reprogramacion.`);
            }
        }
        return this.prisma.tarea.update({
            where: { id: tareaId },
            data: { fechaInicio, fechaFin },
        });
    }
    /* ==================== Export para calendarios ==================== */
    /**
     * Útil para FullCalendar u otros calendarios.
     * Devuelve eventos con título y metadatos de recursos.
     */
    async exportarComoEventosCalendario() {
        const tareas = await this.prisma.tarea.findMany({
            where: {
                conjuntoId: this.conjuntoId,
                estado: { notIn: ESTADOS_NO_CRONOGRAMA },
            },
            include: {
                ubicacion: true,
                elemento: { include: elementoHierarchy_1.elementoParentChainInclude },
                operarios: { include: { usuario: true } },
            },
            orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
        return tareas.map((t) => {
            const nombresOperarios = t.operarios
                .map((o) => o.usuario?.nombre)
                .filter(Boolean)
                .join(", ") || "Sin asignar";
            return {
                title: `${t.descripcion} - ${nombresOperarios}`,
                start: t.fechaInicio.toISOString(),
                end: t.fechaFin.toISOString(),
                resource: {
                    operarios: t.operarios.map((o) => ({
                        id: o.id,
                        nombre: o.usuario?.nombre ?? null,
                    })),
                    ubicacion: t.ubicacion?.nombre ?? null,
                    elemento: (0, elementoHierarchy_1.construirRutaElemento)(t.elemento) ?? null,
                },
            };
        });
    }
}
exports.CronogramaService = CronogramaService;
