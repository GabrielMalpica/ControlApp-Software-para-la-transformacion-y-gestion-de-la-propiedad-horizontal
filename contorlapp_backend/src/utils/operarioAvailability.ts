import type { PrismaClient, Prisma } from "@prisma/client";
import { DiaSemana, EstadoTarea } from "@prisma/client";

type DbClient = PrismaClient | Prisma.TransactionClient;

export type IntervaloLaboral = { i: number; f: number };

export type MotivoIntervaloInvalido =
  | "RANGO_INVALIDO"
  | "CRUZA_DIA"
  | "SIN_HORARIO_CONJUNTO"
  | "FUERA_HORARIO_CONJUNTO"
  | "FUERA_HORARIO_OPERARIO";

type HorarioDia = {
  startMin: number;
  endMin: number;
  descansoStartMin?: number;
  descansoEndMin?: number;
};

export function diaSemanaFromDate(date: Date): DiaSemana {
  const js = date.getDay();
  return [
    DiaSemana.DOMINGO,
    DiaSemana.LUNES,
    DiaSemana.MARTES,
    DiaSemana.MIERCOLES,
    DiaSemana.JUEVES,
    DiaSemana.VIERNES,
    DiaSemana.SABADO,
  ][js] as DiaSemana;
}

export async function obtenerPeriodoDisponibilidadActivo(params: {
  prisma: DbClient;
  operarioId: string;
  fecha: Date;
}) {
  const { prisma, operarioId, fecha } = params;
  const inicioDia = new Date(
    fecha.getFullYear(),
    fecha.getMonth(),
    fecha.getDate(),
    0,
    0,
    0,
    0,
  );
  const finDia = new Date(
    fecha.getFullYear(),
    fecha.getMonth(),
    fecha.getDate(),
    23,
    59,
    59,
    999,
  );
  return prisma.operarioDisponibilidadPeriodo.findFirst({
    where: {
      operarioId,
      fechaInicio: { lte: finDia },
      OR: [{ fechaFin: null }, { fechaFin: { gte: inicioDia } }],
    },
    orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
  });
}

export async function obtenerDisponibilidadActivaOperarios(params: {
  prisma: DbClient;
  operariosIds: string[];
  fecha: Date;
}) {
  const { prisma, operariosIds, fecha } = params;
  const unique = Array.from(new Set(operariosIds.map(String)));
  const entries = await Promise.all(
    unique.map(async (operarioId) => [
      operarioId,
      await obtenerPeriodoDisponibilidadActivo({ prisma, operarioId, fecha }),
    ] as const),
  );
  return new Map(entries);
}

export function diaOperarioBloqueado(params: {
  dia: DiaSemana;
  trabajaDomingo?: boolean | null;
  diaDescanso?: DiaSemana | null;
}) {
  const { dia, trabajaDomingo, diaDescanso } = params;
  if (diaDescanso != null && dia === diaDescanso) return true;
  if (dia === DiaSemana.DOMINGO && !(trabajaDomingo ?? false)) return true;
  return false;
}

export function disponibilidadPermiteDia(params: {
  dia: DiaSemana;
  periodo?: { trabajaDomingo: boolean; diaDescanso: DiaSemana | null } | null;
}) {
  const { dia, periodo } = params;
  return !diaOperarioBloqueado({
    dia,
    trabajaDomingo: periodo?.trabajaDomingo ?? false,
    diaDescanso: periodo?.diaDescanso ?? null,
  });
}

export async function validarOperariosDisponiblesEnFecha(params: {
  prisma: DbClient;
  fecha: Date;
  operariosIds: string[];
}) {
  const { prisma, fecha, operariosIds } = params;
  const dia = diaSemanaFromDate(fecha);
  const disponibilidad = await obtenerDisponibilidadActivaOperarios({
    prisma,
    operariosIds,
    fecha,
  });

  const noDisponibles: string[] = [];
  for (const id of Array.from(new Set(operariosIds.map(String)))) {
    const ok = disponibilidadPermiteDia({
      dia,
      periodo: disponibilidad.get(id)
        ? {
            trabajaDomingo: disponibilidad.get(id)!.trabajaDomingo,
            diaDescanso: disponibilidad.get(id)!.diaDescanso,
          }
        : null,
    });
    if (!ok) noDisponibles.push(id);
  }

  return {
    dia,
    noDisponibles,
    ok: noDisponibles.length === 0,
  };
}

export async function validarOperariosDisponiblesEnRango(params: {
  prisma: DbClient;
  fechaInicio: Date;
  fechaFin: Date;
  operariosIds: string[];
  horarioDia: HorarioDia;
  jornadasByOperario: Map<string, { jornadaLaboral: string | null; patronJornada: string | null }>;
}) {
  const { prisma, fechaInicio, fechaFin, operariosIds, horarioDia, jornadasByOperario } = params;
  const dia = diaSemanaFromDate(fechaInicio);
  const disponibilidad = await obtenerDisponibilidadActivaOperarios({
    prisma,
    operariosIds,
    fecha: fechaInicio,
  });

  const iniMin = fechaInicio.getHours() * 60 + fechaInicio.getMinutes();
  const finMin = fechaFin.getHours() * 60 + fechaFin.getMinutes();
  const noDisponibles: string[] = [];

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
    if (!ok) noDisponibles.push(id);
  }

  return { ok: noDisponibles.length === 0, noDisponibles };
}

function inicioSemana(fecha: Date) {
  const x = new Date(fecha);
  x.setHours(0, 0, 0, 0);
  x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
  return x;
}

async function capacidadSemanalOperario(params: {
  prisma: DbClient;
  conjuntoId: string;
  operarioId: string;
  fechaReferencia: Date;
}) {
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
  const limiteSemana =
    (conjunto?.limiteHorasSemanaOverride ??
      conjunto?.empresa?.limiteHorasSemana ??
      jornadas?.empresa?.limiteHorasSemana ??
      42) * 60;
  let total = 0;

  const toMin = (value: unknown) => {
    const text = String(value ?? "").trim();
    const match = text.match(/(\d{1,2}):(\d{2})/);
    if (!match) return null;
    return Number(match[1]) * 60 + Number(match[2]);
  };

  for (let offset = 0; offset < 7; offset++) {
    const fecha = new Date(monday);
    fecha.setDate(monday.getDate() + offset);
    const ds = diaSemanaFromDate(fecha);
    const horario = horarios.find((h) => String(h.dia) === String(ds));
    if (!horario) continue;
    const startMin = toMin(horario.horaApertura);
    const endMin = toMin(horario.horaCierre);
    if (startMin == null || endMin == null || endMin <= startMin) continue;

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
    for (const slot of allowed) total += slot.f - slot.i;
  }

  return Math.min(total, limiteSemana);
}

async function minutosAsignadosSemana(params: {
  prisma: DbClient;
  conjuntoId: string;
  operarioId: string;
  fechaReferencia: Date;
  excluirTareaId?: number;
}) {
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
      estado: { notIn: [EstadoTarea.RECHAZADA] },
    },
    select: { duracionMinutos: true },
  });

  return tareas.reduce((sum, t) => sum + (t.duracionMinutos ?? 0), 0);
}

export async function validarLimiteSemanalOperarios(params: {
  prisma: DbClient;
  conjuntoId: string;
  operariosIds: string[];
  fechaInicio: Date;
  duracionMinutos: number;
  excluirTareaId?: number;
}) {
  const { prisma, conjuntoId, operariosIds, fechaInicio, duracionMinutos, excluirTareaId } = params;
  const excedidos: string[] = [];
  for (const operarioId of Array.from(new Set(operariosIds.map(String)))) {
    const [capacidad, usados] = await Promise.all([
      capacidadSemanalOperario({ prisma, conjuntoId, operarioId, fechaReferencia: fechaInicio }),
      minutosAsignadosSemana({ prisma, conjuntoId, operarioId, fechaReferencia: fechaInicio, excluirTareaId }),
    ]);
    if (usados + duracionMinutos > capacidad) excedidos.push(operarioId);
  }
  return { ok: excedidos.length === 0, excedidos };
}

export function allowedIntervalsForUserWithAvailability(params: {
  dia: DiaSemana;
  horario: HorarioDia;
  jornadaLaboral: string | null;
  patronJornada: string | null;
  disponibilidad?: { trabajaDomingo: boolean; diaDescanso: DiaSemana | null } | null;
}) {
  const { dia, horario, jornadaLaboral, patronJornada, disponibilidad } = params;

  if (!disponibilidadPermiteDia({ dia, periodo: disponibilidad })) {
    return [] as Array<{ i: number; f: number }>;
  }

  const diaPatron =
    dia === DiaSemana.DOMINGO &&
    (disponibilidad?.trabajaDomingo ?? false) &&
    disponibilidad?.diaDescanso != null &&
    disponibilidad.diaDescanso !== DiaSemana.DOMINGO
      ? disponibilidad.diaDescanso
      : dia;

  const intervalosConjunto = workIntervalsFromHorario(horario);

  // Compatibilidad con usuarios antiguos sin jornada: se consideran de jornada
  // completa, pero nunca por fuera del horario (ni del descanso) del conjunto.
  if (!jornadaLaboral || jornadaLaboral === "COMPLETA") {
    return intervalosConjunto;
  }

  if (jornadaLaboral === "FINES_DE_SEMANA") {
    return dia === DiaSemana.SABADO || dia === DiaSemana.DOMINGO
      ? intervalosConjunto
      : [];
  }

  if (jornadaLaboral !== "MEDIO_TIEMPO") return [];

  const apertura = horario.startMin;
  const cierre = horario.endMin;
  const descansoInicio = horario.descansoStartMin;
  const descansoFin = horario.descansoEndMin;

  const beforeLunch =
    descansoInicio != null && descansoInicio > apertura
      ? { i: apertura, f: Math.min(descansoInicio, cierre) }
      : null;
  const afterLunch =
    descansoFin != null && descansoFin < cierre
      ? { i: Math.max(descansoFin, apertura), f: cierre }
      : null;

  const morningFallbackEnd = Math.min(cierre, apertura + 4 * 60);
  const beforeLunchEffective =
    beforeLunch != null && beforeLunch.f > beforeLunch.i
      ? beforeLunch
      : morningFallbackEnd > apertura
        ? { i: apertura, f: morningFallbackEnd }
        : null;

  const afterLunchEffective =
    afterLunch != null && afterLunch.f > afterLunch.i ? afterLunch : null;

  const p = patronJornada as string | null;
  if (!p) return [];

  if (p === "MEDIO_DIAS_INTERCALADOS") {
    if (
      diaPatron === DiaSemana.LUNES ||
      diaPatron === DiaSemana.MIERCOLES ||
      diaPatron === DiaSemana.VIERNES ||
      diaPatron === DiaSemana.SABADO
    ) {
      return intervalosConjunto;
    }
    return [];
  }

  if (p === "MEDIO_SEMANA_SABADO") {
    if (
      diaPatron === DiaSemana.LUNES ||
      diaPatron === DiaSemana.MARTES ||
      diaPatron === DiaSemana.MIERCOLES ||
      diaPatron === DiaSemana.JUEVES ||
      diaPatron === DiaSemana.VIERNES
    ) {
      return beforeLunchEffective != null ? [beforeLunchEffective] : [];
    }
    if (diaPatron === DiaSemana.SABADO) {
      return intervalosConjunto;
    }
    return [];
  }

  if (p === "MEDIO_SEMANA_SABADO_TARDE") {
    if (
      diaPatron === DiaSemana.LUNES ||
      diaPatron === DiaSemana.MARTES ||
      diaPatron === DiaSemana.MIERCOLES ||
      diaPatron === DiaSemana.JUEVES ||
      diaPatron === DiaSemana.VIERNES
    ) {
      return afterLunchEffective != null ? [afterLunchEffective] : [];
    }
    if (diaPatron === DiaSemana.SABADO) {
      return intervalosConjunto;
    }
    return [];
  }

  return [] as Array<{ i: number; f: number }>;
}

function workIntervalsFromHorario(horario: HorarioDia): IntervaloLaboral[] {
  if (horario.endMin <= horario.startMin) return [];
  const ds = horario.descansoStartMin;
  const df = horario.descansoEndMin;
  if (
    ds == null ||
    df == null ||
    ds <= horario.startMin ||
    df <= ds ||
    df >= horario.endMin
  ) {
    return [{ i: horario.startMin, f: horario.endMin }];
  }
  return [
    { i: horario.startMin, f: ds },
    { i: df, f: horario.endMin },
  ];
}

function intersectIntervals(
  left: IntervaloLaboral[],
  right: IntervaloLaboral[],
): IntervaloLaboral[] {
  const out: IntervaloLaboral[] = [];
  for (const a of left) {
    for (const b of right) {
      const i = Math.max(a.i, b.i);
      const f = Math.min(a.f, b.f);
      if (f > i) out.push({ i, f });
    }
  }
  return out.sort((a, b) => a.i - b.i);
}

export function parseHorarioMinutos(value: unknown): number | null {
  const text = String(value ?? "").trim();
  const match = /^(\d{1,2}):(\d{2})$/.exec(text);
  if (!match) return null;
  const horas = Number(match[1]);
  const minutos = Number(match[2]);
  if (horas < 0 || horas > 23 || minutos < 0 || minutos > 59) return null;
  return horas * 60 + minutos;
}

export async function obtenerIntervalosEfectivosProgramacion(params: {
  prisma: DbClient;
  conjuntoId: string;
  fecha: Date;
  operariosIds?: string[];
}): Promise<{
  dia: DiaSemana;
  horario: HorarioDia | null;
  intervalosConjunto: IntervaloLaboral[];
  intervalosEfectivos: IntervaloLaboral[];
  operariosSinConfiguracion: string[];
}> {
  const { prisma, conjuntoId, fecha } = params;
  const operariosIds = Array.from(new Set((params.operariosIds ?? []).map(String)));
  const dia = diaSemanaFromDate(fecha);
  const horarioRepo = (prisma as any).conjuntoHorario;
  const horarioSelect = {
    horaApertura: true,
    horaCierre: true,
    descansoInicio: true,
    descansoFin: true,
  };
  const row = horarioRepo?.findUnique
    ? await horarioRepo.findUnique({
        where: { conjuntoId_dia: { conjuntoId, dia } },
        select: horarioSelect,
      })
    : horarioRepo?.findFirst
      ? await horarioRepo.findFirst({
          where: { conjuntoId, dia },
          select: horarioSelect,
        })
      : null;

  if (!row) {
    return {
      dia,
      horario: null,
      intervalosConjunto: [],
      intervalosEfectivos: [],
      operariosSinConfiguracion: [],
    };
  }

  const startMin = parseHorarioMinutos(row.horaApertura);
  const endMin = parseHorarioMinutos(row.horaCierre);
  if (startMin == null || endMin == null || endMin <= startMin) {
    return {
      dia,
      horario: null,
      intervalosConjunto: [],
      intervalosEfectivos: [],
      operariosSinConfiguracion: [],
    };
  }

  const horario: HorarioDia = {
    startMin,
    endMin,
    descansoStartMin: row.descansoInicio
      ? parseHorarioMinutos(row.descansoInicio) ?? undefined
      : undefined,
    descansoEndMin: row.descansoFin
      ? parseHorarioMinutos(row.descansoFin) ?? undefined
      : undefined,
  };
  const intervalosConjunto = workIntervalsFromHorario(horario);
  if (!operariosIds.length) {
    return {
      dia,
      horario,
      intervalosConjunto,
      intervalosEfectivos: intervalosConjunto,
      operariosSinConfiguracion: [],
    };
  }

  const [operarios, disponibilidad] = await Promise.all([
    prisma.operario.findMany({
      where: { id: { in: operariosIds } },
      select: {
        id: true,
        usuario: { select: { jornadaLaboral: true, patronJornada: true } },
      },
    }),
    obtenerDisponibilidadActivaOperarios({ prisma, operariosIds, fecha }),
  ]);
  const byId = new Map(operarios.map((operario) => [operario.id, operario]));
  const operariosSinConfiguracion = operariosIds.filter((id) => !byId.has(id));
  let intervalosEfectivos = intervalosConjunto;

  for (const operarioId of operariosIds) {
    const operario = byId.get(operarioId);
    if (!operario) {
      intervalosEfectivos = [];
      continue;
    }
    const periodo = disponibilidad.get(operarioId);
    const permitidos = allowedIntervalsForUserWithAvailability({
      dia,
      horario,
      jornadaLaboral: operario.usuario?.jornadaLaboral ?? null,
      patronJornada: operario.usuario?.patronJornada ?? null,
      disponibilidad: periodo
        ? {
            trabajaDomingo: periodo.trabajaDomingo,
            diaDescanso: periodo.diaDescanso,
          }
        : null,
    });
    intervalosEfectivos = intersectIntervals(intervalosEfectivos, permitidos);
    if (!intervalosEfectivos.length) break;
  }

  return {
    dia,
    horario,
    intervalosConjunto,
    intervalosEfectivos,
    operariosSinConfiguracion,
  };
}

export async function validarIntervaloProgramacion(params: {
  prisma: DbClient;
  conjuntoId: string;
  fechaInicio: Date;
  fechaFin: Date;
  operariosIds?: string[];
}): Promise<
  | { ok: true; intervalo: IntervaloLaboral }
  | { ok: false; motivo: MotivoIntervaloInvalido; mensaje: string }
> {
  const { fechaInicio, fechaFin } = params;
  if (!(fechaFin > fechaInicio)) {
    return {
      ok: false,
      motivo: "RANGO_INVALIDO",
      mensaje: "La fecha final debe ser posterior a la fecha inicial.",
    };
  }
  if (
    fechaInicio.getFullYear() !== fechaFin.getFullYear() ||
    fechaInicio.getMonth() !== fechaFin.getMonth() ||
    fechaInicio.getDate() !== fechaFin.getDate()
  ) {
    return {
      ok: false,
      motivo: "CRUZA_DIA",
      mensaje: "Cada bloque debe quedar completamente dentro del mismo día.",
    };
  }

  const disponibilidad = await obtenerIntervalosEfectivosProgramacion({
    prisma: params.prisma,
    conjuntoId: params.conjuntoId,
    fecha: fechaInicio,
    operariosIds: params.operariosIds,
  });
  if (!disponibilidad.horario) {
    return {
      ok: false,
      motivo: "SIN_HORARIO_CONJUNTO",
      mensaje: "El conjunto no tiene un horario laboral válido para ese día.",
    };
  }
  const inicioMin = fechaInicio.getHours() * 60 + fechaInicio.getMinutes();
  const finMin = fechaFin.getHours() * 60 + fechaFin.getMinutes();
  const dentroConjunto = disponibilidad.intervalosConjunto.some(
    (intervalo) => inicioMin >= intervalo.i && finMin <= intervalo.f,
  );
  if (!dentroConjunto) {
    return {
      ok: false,
      motivo: "FUERA_HORARIO_CONJUNTO",
      mensaje:
        "La tarea queda por fuera del horario o sobre el descanso configurado para el conjunto.",
    };
  }
  const efectivo = disponibilidad.intervalosEfectivos.find(
    (intervalo) => inicioMin >= intervalo.i && finMin <= intervalo.f,
  );
  if (!efectivo) {
    return {
      ok: false,
      motivo: "FUERA_HORARIO_OPERARIO",
      mensaje:
        "El intervalo completo no está dentro de la jornada disponible de todos los operarios asignados.",
    };
  }
  return { ok: true, intervalo: efectivo };
}
