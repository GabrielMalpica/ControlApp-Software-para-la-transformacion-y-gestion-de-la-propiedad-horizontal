"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.diaSemanaFromDate = diaSemanaFromDate;
exports.obtenerPeriodoDisponibilidadActivo = obtenerPeriodoDisponibilidadActivo;
exports.obtenerDisponibilidadActivaOperarios = obtenerDisponibilidadActivaOperarios;
exports.diaOperarioBloqueado = diaOperarioBloqueado;
exports.disponibilidadPermiteDia = disponibilidadPermiteDia;
exports.validarOperariosDisponiblesEnFecha = validarOperariosDisponiblesEnFecha;
exports.validarOperariosDisponiblesEnRango = validarOperariosDisponiblesEnRango;
exports.validarLimiteSemanalOperarios = validarLimiteSemanalOperarios;
exports.allowedIntervalsForUserWithAvailability = allowedIntervalsForUserWithAvailability;
const client_1 = require("@prisma/client");
function diaSemanaFromDate(date) {
    const js = date.getDay();
    return [
        client_1.DiaSemana.DOMINGO,
        client_1.DiaSemana.LUNES,
        client_1.DiaSemana.MARTES,
        client_1.DiaSemana.MIERCOLES,
        client_1.DiaSemana.JUEVES,
        client_1.DiaSemana.VIERNES,
        client_1.DiaSemana.SABADO,
    ][js];
}
async function obtenerPeriodoDisponibilidadActivo(params) {
    const { prisma, operarioId, fecha } = params;
    return prisma.operarioDisponibilidadPeriodo.findFirst({
        where: {
            operarioId,
            fechaInicio: { lte: fecha },
            OR: [{ fechaFin: null }, { fechaFin: { gte: fecha } }],
        },
        orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
    });
}
async function obtenerDisponibilidadActivaOperarios(params) {
    const { prisma, operariosIds, fecha } = params;
    const unique = Array.from(new Set(operariosIds.map(String)));
    const entries = await Promise.all(unique.map(async (operarioId) => [
        operarioId,
        await obtenerPeriodoDisponibilidadActivo({ prisma, operarioId, fecha }),
    ]));
    return new Map(entries);
}
function diaOperarioBloqueado(params) {
    const { dia, trabajaDomingo, diaDescanso } = params;
    if (diaDescanso != null && dia === diaDescanso)
        return true;
    if (dia === client_1.DiaSemana.DOMINGO && !(trabajaDomingo ?? false))
        return true;
    return false;
}
function disponibilidadPermiteDia(params) {
    const { dia, periodo } = params;
    return !diaOperarioBloqueado({
        dia,
        trabajaDomingo: periodo?.trabajaDomingo ?? false,
        diaDescanso: periodo?.diaDescanso ?? null,
    });
}
async function validarOperariosDisponiblesEnFecha(params) {
    const { prisma, fecha, operariosIds } = params;
    const dia = diaSemanaFromDate(fecha);
    const disponibilidad = await obtenerDisponibilidadActivaOperarios({
        prisma,
        operariosIds,
        fecha,
    });
    const noDisponibles = [];
    for (const id of Array.from(new Set(operariosIds.map(String)))) {
        const ok = disponibilidadPermiteDia({
            dia,
            periodo: disponibilidad.get(id)
                ? {
                    trabajaDomingo: disponibilidad.get(id).trabajaDomingo,
                    diaDescanso: disponibilidad.get(id).diaDescanso,
                }
                : null,
        });
        if (!ok)
            noDisponibles.push(id);
    }
    return {
        dia,
        noDisponibles,
        ok: noDisponibles.length === 0,
    };
}
async function validarOperariosDisponiblesEnRango(params) {
    const { prisma, fechaInicio, fechaFin, operariosIds, horarioDia, jornadasByOperario } = params;
    const dia = diaSemanaFromDate(fechaInicio);
    const disponibilidad = await obtenerDisponibilidadActivaOperarios({
        prisma,
        operariosIds,
        fecha: fechaInicio,
    });
    const iniMin = fechaInicio.getHours() * 60 + fechaInicio.getMinutes();
    const finMin = fechaFin.getHours() * 60 + fechaFin.getMinutes();
    const noDisponibles = [];
    for (const id of Array.from(new Set(operariosIds.map(String)))) {
        const jornada = jornadasByOperario.get(id);
        const periodo = disponibilidad.get(id);
        const allowed = allowedIntervalsForUserWithAvailability({
            dia,
            horario: horarioDia,
            jornadaLaboral: jornada?.jornadaLaboral ?? null,
            patronJornada: jornada?.patronJornada ?? null,
            disponibilidad: periodo
                ? {
                    trabajaDomingo: periodo.trabajaDomingo,
                    diaDescanso: periodo.diaDescanso,
                }
                : null,
        });
        const ok = allowed.some((slot) => iniMin >= slot.i && finMin <= slot.f);
        if (!ok)
            noDisponibles.push(id);
    }
    return { ok: noDisponibles.length === 0, noDisponibles };
}
function inicioSemana(fecha) {
    const x = new Date(fecha);
    x.setHours(0, 0, 0, 0);
    x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
    return x;
}
async function capacidadSemanalOperario(params) {
    const { prisma, conjuntoId, operarioId, fechaReferencia } = params;
    const monday = inicioSemana(fechaReferencia);
    const horarios = await prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
    const jornadas = await prisma.operario.findUnique({
        where: { id: operarioId },
        select: {
            usuario: { select: { jornadaLaboral: true, patronJornada: true } },
            empresa: { select: { limiteHorasSemana: true } },
        },
    });
    const conjunto = await prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: {
            limiteHorasSemanaOverride: true,
            empresa: { select: { limiteHorasSemana: true } },
        },
    });
    const jornadaLaboral = jornadas?.usuario?.jornadaLaboral ?? null;
    const patronJornada = jornadas?.usuario?.patronJornada ?? null;
    const limiteSemana = (conjunto?.limiteHorasSemanaOverride ??
        conjunto?.empresa?.limiteHorasSemana ??
        jornadas?.empresa?.limiteHorasSemana ??
        42) * 60;
    let total = 0;
    const toMin = (value) => {
        const text = String(value ?? "").trim();
        const match = text.match(/(\d{1,2}):(\d{2})/);
        if (!match)
            return null;
        return Number(match[1]) * 60 + Number(match[2]);
    };
    for (let offset = 0; offset < 7; offset++) {
        const fecha = new Date(monday);
        fecha.setDate(monday.getDate() + offset);
        const ds = diaSemanaFromDate(fecha);
        const horario = horarios.find((h) => String(h.dia) === String(ds));
        if (!horario)
            continue;
        const startMin = toMin(horario.horaApertura);
        const endMin = toMin(horario.horaCierre);
        if (startMin == null || endMin == null || endMin <= startMin)
            continue;
        const periodo = await obtenerPeriodoDisponibilidadActivo({ prisma, operarioId, fecha });
        const allowed = allowedIntervalsForUserWithAvailability({
            dia: ds,
            horario: {
                startMin,
                endMin,
                descansoStartMin: horario.descansoInicio ? toMin(horario.descansoInicio) ?? undefined : undefined,
                descansoEndMin: horario.descansoFin ? toMin(horario.descansoFin) ?? undefined : undefined,
            },
            jornadaLaboral,
            patronJornada,
            disponibilidad: periodo
                ? { trabajaDomingo: periodo.trabajaDomingo, diaDescanso: periodo.diaDescanso }
                : null,
        });
        for (const slot of allowed)
            total += slot.f - slot.i;
    }
    return Math.min(total, limiteSemana);
}
async function minutosAsignadosSemana(params) {
    const { prisma, conjuntoId, operarioId, fechaReferencia, excluirTareaId } = params;
    const ini = inicioSemana(fechaReferencia);
    const fin = new Date(ini);
    fin.setDate(ini.getDate() + 6);
    fin.setHours(23, 59, 59, 999);
    const tareas = await prisma.tarea.findMany({
        where: {
            conjuntoId,
            operarios: { some: { id: operarioId } },
            fechaInicio: { lte: fin },
            fechaFin: { gte: ini },
            ...(excluirTareaId != null ? { id: { not: excluirTareaId } } : {}),
            estado: { notIn: [client_1.EstadoTarea.RECHAZADA] },
        },
        select: { duracionMinutos: true },
    });
    return tareas.reduce((sum, t) => sum + (t.duracionMinutos ?? 0), 0);
}
async function validarLimiteSemanalOperarios(params) {
    const { prisma, conjuntoId, operariosIds, fechaInicio, duracionMinutos, excluirTareaId } = params;
    const excedidos = [];
    for (const operarioId of Array.from(new Set(operariosIds.map(String)))) {
        const [capacidad, usados] = await Promise.all([
            capacidadSemanalOperario({ prisma, conjuntoId, operarioId, fechaReferencia: fechaInicio }),
            minutosAsignadosSemana({ prisma, conjuntoId, operarioId, fechaReferencia: fechaInicio, excluirTareaId }),
        ]);
        if (usados + duracionMinutos > capacidad)
            excedidos.push(operarioId);
    }
    return { ok: excedidos.length === 0, excedidos };
}
function allowedIntervalsForUserWithAvailability(params) {
    const { dia, horario, jornadaLaboral, patronJornada, disponibilidad } = params;
    if (!disponibilidadPermiteDia({ dia, periodo: disponibilidad })) {
        return [];
    }
    const diaPatron = dia === client_1.DiaSemana.DOMINGO &&
        (disponibilidad?.trabajaDomingo ?? false) &&
        disponibilidad?.diaDescanso != null &&
        disponibilidad.diaDescanso !== client_1.DiaSemana.DOMINGO
        ? disponibilidad.diaDescanso
        : dia;
    if (!jornadaLaboral)
        return [{ i: horario.startMin, f: horario.endMin }];
    if (jornadaLaboral === "COMPLETA") {
        return [{ i: horario.startMin, f: horario.endMin }];
    }
    if (jornadaLaboral !== "MEDIO_TIEMPO") {
        return [{ i: horario.startMin, f: horario.endMin }];
    }
    const apertura = horario.startMin;
    const cierre = horario.endMin;
    const descansoInicio = horario.descansoStartMin;
    const descansoFin = horario.descansoEndMin;
    const beforeLunch = descansoInicio != null && descansoInicio > apertura
        ? { i: apertura, f: Math.min(descansoInicio, cierre) }
        : null;
    const afterLunch = descansoFin != null && descansoFin < cierre
        ? { i: Math.max(descansoFin, apertura), f: cierre }
        : null;
    const morningFallbackEnd = Math.min(cierre, apertura + 4 * 60);
    const beforeLunchEffective = beforeLunch != null && beforeLunch.f > beforeLunch.i
        ? beforeLunch
        : morningFallbackEnd > apertura
            ? { i: apertura, f: morningFallbackEnd }
            : null;
    const afterLunchEffective = afterLunch != null && afterLunch.f > afterLunch.i ? afterLunch : null;
    const p = patronJornada;
    if (!p)
        return [];
    if (p === "MEDIO_DIAS_INTERCALADOS") {
        if (diaPatron === client_1.DiaSemana.LUNES ||
            diaPatron === client_1.DiaSemana.MIERCOLES ||
            diaPatron === client_1.DiaSemana.VIERNES ||
            diaPatron === client_1.DiaSemana.SABADO) {
            return [{ i: apertura, f: cierre }];
        }
        return [];
    }
    if (p === "MEDIO_SEMANA_SABADO") {
        if (diaPatron === client_1.DiaSemana.LUNES ||
            diaPatron === client_1.DiaSemana.MARTES ||
            diaPatron === client_1.DiaSemana.MIERCOLES ||
            diaPatron === client_1.DiaSemana.JUEVES ||
            diaPatron === client_1.DiaSemana.VIERNES) {
            return beforeLunchEffective != null ? [beforeLunchEffective] : [];
        }
        if (diaPatron === client_1.DiaSemana.SABADO) {
            return [{ i: apertura, f: cierre }];
        }
        return [];
    }
    if (p === "MEDIO_SEMANA_SABADO_TARDE") {
        if (diaPatron === client_1.DiaSemana.LUNES ||
            diaPatron === client_1.DiaSemana.MARTES ||
            diaPatron === client_1.DiaSemana.MIERCOLES ||
            diaPatron === client_1.DiaSemana.JUEVES ||
            diaPatron === client_1.DiaSemana.VIERNES) {
            return afterLunchEffective != null ? [afterLunchEffective] : [];
        }
        if (diaPatron === client_1.DiaSemana.SABADO) {
            return [{ i: apertura, f: cierre }];
        }
        return [];
    }
    return [];
}
