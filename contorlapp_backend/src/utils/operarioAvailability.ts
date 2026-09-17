import type { PrismaClient, Prisma } from "@prisma/client";
import { DiaSemana, EstadoTarea } from "@prisma/client";
// Mismo tipo que usa el generador de cronograma (DefinicionTareaPreventivaService.ts).
// Se reutiliza en vez de duplicarlo: son estructuralmente idénticos.
import type { HorarioDia } from "./agenda";

type DbClient = PrismaClient | Prisma.TransactionClient;

export type IntervaloLaboral = { i: number; f: number };

export type MotivoIntervaloInvalido =
  | "RANGO_INVALIDO"
  | "CRUZA_DIA"
  | "SIN_HORARIO_CONJUNTO"
  | "FUERA_HORARIO_CONJUNTO"
  | "FUERA_HORARIO_OPERARIO";

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

/**
 * Antes, un operario sin `trabajaDomingo=true` (o con `diaDescanso` ese día)
 * en su periodo de disponibilidad quedaba bloqueado ese día sin importar el
 * horario. Con las necesidades operativas (plazas), qué días trabaja un
 * operario ya lo dice su horario efectivo (el de su plaza, o el heredado del
 * conjunto): si un día no tiene fila configurada, `horarioEfectivo` es `null`
 * y `allowedIntervalsForUserWithAvailability` ya no da intervalos ese día.
 * Esta función queda como no-operación (nunca bloquea) para no romper a los
 * ~9 llamadores existentes; la tabla `OperarioDisponibilidadPeriodo` se
 * conserva por compatibilidad con datos históricos, pero ya no gatilla nada.
 */
export async function validarOperariosDisponiblesEnFecha(params: {
  prisma: DbClient;
  fecha: Date;
  operariosIds: string[];
}) {
  return {
    dia: diaSemanaFromDate(params.fecha),
    noDisponibles: [] as string[],
    ok: true,
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

  for (let offset = 0; offset < 7; offset++) {
    const fecha = new Date(monday);
    fecha.setDate(monday.getDate() + offset);
    const ds = diaSemanaFromDate(fecha);
    // Horario efectivo del operario ese día: el de su plaza si tiene horario
    // especial, o el heredado del conjunto (comportamiento previo intacto
    // cuando no hay necesidades configuradas).
    const horarioEfectivo = await obtenerHorarioEfectivoOperario({
      prisma,
      conjuntoId,
      operarioId,
      dia: ds,
    });
    if (!horarioEfectivo) continue;

    const periodo = await obtenerPeriodoDisponibilidadActivo({ prisma, operarioId, fecha });
    const allowed = allowedIntervalsForUserWithAvailability({
      dia: ds,
      horario: horarioEfectivo,
      horarioEfectivo,
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
  /**
   * Ventana base efectiva del operario para este día: el horario de su plaza
   * (ConjuntoNecesidadOperario) si tiene horario especial, o el heredado del
   * conjunto en caso contrario. Si se omite (undefined), se usa `horario` tal
   * cual — idéntico al comportamiento previo a las necesidades operativas. Si
   * se pasa `null` explícito, el operario no tiene ventana ese día (p.ej. su
   * plaza no trabaja ese día) y no hay intervalos permitidos.
   */
  horarioEfectivo?: HorarioDia | null;
}) {
  const { dia, jornadaLaboral, patronJornada, disponibilidad } = params;
  const horario =
    params.horarioEfectivo === undefined ? params.horario : params.horarioEfectivo;

  // Qué días trabaja el operario ya lo dice `horario` (el de su plaza, o el
  // heredado del conjunto): un `trabajaDomingo=false`/`diaDescanso` en su
  // periodo de disponibilidad ya no bloquea por separado (ver comentario en
  // validarOperariosDisponiblesEnFecha). `disponibilidad` se conserva solo
  // para reasignar `diaPatron` más abajo (patrones de jornada parcial).
  if (!horario) {
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

const horarioColumnasSelect = {
  horaApertura: true,
  horaCierre: true,
  descansoInicio: true,
  descansoFin: true,
} as const;

function rowToHorarioDia(
  row:
    | {
        horaApertura: unknown;
        horaCierre: unknown;
        descansoInicio?: unknown;
        descansoFin?: unknown;
      }
    | null
    | undefined,
): HorarioDia | null {
  if (!row) return null;
  const startMin = parseHorarioMinutos(row.horaApertura);
  const endMin = parseHorarioMinutos(row.horaCierre);
  if (startMin == null || endMin == null || endMin <= startMin) return null;
  return {
    startMin,
    endMin,
    descansoStartMin: row.descansoInicio
      ? parseHorarioMinutos(row.descansoInicio) ?? undefined
      : undefined,
    descansoEndMin: row.descansoFin
      ? parseHorarioMinutos(row.descansoFin) ?? undefined
      : undefined,
  };
}

async function obtenerHorarioGeneralConjunto(params: {
  prisma: DbClient;
  conjuntoId: string;
  dia: DiaSemana;
}): Promise<HorarioDia | null> {
  const { prisma, conjuntoId, dia } = params;
  const horarioRepo = (prisma as any).conjuntoHorario;
  const row = horarioRepo?.findUnique
    ? await horarioRepo.findUnique({
        where: { conjuntoId_dia: { conjuntoId, dia } },
        select: horarioColumnasSelect,
      })
    : horarioRepo?.findFirst
      ? await horarioRepo.findFirst({
          where: { conjuntoId, dia },
          select: horarioColumnasSelect,
        })
      : null;
  return rowToHorarioDia(row);
}

/**
 * Horario efectivo de un operario para un día: el de su plaza
 * (ConjuntoNecesidadOperario) si tiene horario especial activo, o el
 * heredado del conjunto en caso contrario (comportamiento actual). `null`
 * significa que ese operario no tiene ventana ese día (p.ej. su plaza tiene
 * horario especial pero no configuró ese día, o el conjunto tampoco opera).
 * Resuelve varios operarios en una sola consulta por tabla para evitar N+1
 * dentro del generador de cronograma.
 */
export async function obtenerHorariosEfectivosOperarios(params: {
  prisma: DbClient;
  conjuntoId: string;
  operariosIds: string[];
  dia: DiaSemana;
}): Promise<Map<string, HorarioDia | null>> {
  const { prisma, conjuntoId, dia } = params;
  const operariosIds = Array.from(new Set(params.operariosIds.map(String)));
  const resultado = new Map<string, HorarioDia | null>();
  if (!operariosIds.length) return resultado;

  const necesidadRepo = (prisma as any).conjuntoNecesidadOperario;
  const necesidades = necesidadRepo?.findMany
    ? await necesidadRepo.findMany({
        where: { conjuntoId, operarioId: { in: operariosIds }, activo: true },
        select: {
          operarioId: true,
          horarioEspecial: true,
          horarios: { where: { dia }, select: horarioColumnasSelect },
        },
      })
    : [];
  const necesidadPorOperario = new Map<string, (typeof necesidades)[number]>(
    necesidades
      .filter((n: any) => n.operarioId)
      .map((n: any) => [n.operarioId as string, n]),
  );

  // El horario general se consulta como máximo una vez, aunque varios
  // operarios caigan en el fallback (sin plaza o sin horario especial).
  let horarioGeneral: HorarioDia | null | undefined;
  const resolverHorarioGeneral = async () => {
    if (horarioGeneral === undefined) {
      horarioGeneral = await obtenerHorarioGeneralConjunto({ prisma, conjuntoId, dia });
    }
    return horarioGeneral;
  };

  for (const operarioId of operariosIds) {
    const necesidad = necesidadPorOperario.get(operarioId);
    if (necesidad?.horarioEspecial) {
      // Plaza con horario propio: sobrescribe, incluso si excede o no
      // coincide con el horario general del conjunto (puede no tener fila
      // ese día -> null -> la plaza no trabaja ese día).
      resultado.set(operarioId, rowToHorarioDia(necesidad.horarios[0] ?? null));
      continue;
    }
    resultado.set(operarioId, await resolverHorarioGeneral());
  }
  return resultado;
}

/** Variante para un solo operario; delega en la versión en lote. */
export async function obtenerHorarioEfectivoOperario(params: {
  prisma: DbClient;
  conjuntoId: string;
  operarioId: string;
  dia: DiaSemana;
}): Promise<HorarioDia | null> {
  const mapa = await obtenerHorariosEfectivosOperarios({
    prisma: params.prisma,
    conjuntoId: params.conjuntoId,
    operariosIds: [params.operarioId],
    dia: params.dia,
  });
  return mapa.get(params.operarioId) ?? null;
}

/** Unión de intervalos (a diferencia de intersectIntervals, que es AND). */
function unionIntervals(
  left: IntervaloLaboral[],
  right: IntervaloLaboral[],
): IntervaloLaboral[] {
  const ordenados = [...left, ...right].sort((a, b) => a.i - b.i);
  const fusionados: IntervaloLaboral[] = [];
  for (const actual of ordenados) {
    const ultimo = fusionados[fusionados.length - 1];
    if (ultimo && actual.i <= ultimo.f) {
      ultimo.f = Math.max(ultimo.f, actual.f);
    } else {
      fusionados.push({ ...actual });
    }
  }
  return fusionados;
}

export async function obtenerIntervalosEfectivosProgramacion(params: {
  prisma: DbClient;
  conjuntoId: string;
  fecha: Date;
  operariosIds?: string[];
}): Promise<{
  dia: DiaSemana;
  /** Horario general del CONJUNTO ese día (sin cambios de significado). */
  horario: HorarioDia | null;
  /**
   * Ventana de búsqueda: el horario del conjunto si no se pasan operarios,
   * o la UNIÓN de las ventanas efectivas de los operarios (conjunto o plaza
   * con horario especial) si se pasan. Puede exceder el horario del
   * conjunto cuando una plaza tiene horario especial más amplio.
   */
  intervalosConjunto: IntervaloLaboral[];
  /** Intersección tras aplicar jornada/patrón/disponibilidad de cada operario. */
  intervalosEfectivos: IntervaloLaboral[];
  operariosSinConfiguracion: string[];
}> {
  const { prisma, conjuntoId, fecha } = params;
  const operariosIds = Array.from(new Set((params.operariosIds ?? []).map(String)));
  const dia = diaSemanaFromDate(fecha);
  const horarioGeneral = await obtenerHorarioGeneralConjunto({ prisma, conjuntoId, dia });

  if (!operariosIds.length) {
    const intervalosConjunto = horarioGeneral ? workIntervalsFromHorario(horarioGeneral) : [];
    return {
      dia,
      horario: horarioGeneral,
      intervalosConjunto,
      intervalosEfectivos: intervalosConjunto,
      operariosSinConfiguracion: [],
    };
  }

  const [operarios, disponibilidad, horariosEfectivos] = await Promise.all([
    prisma.operario.findMany({
      where: { id: { in: operariosIds } },
      select: {
        id: true,
        usuario: { select: { jornadaLaboral: true, patronJornada: true } },
      },
    }),
    obtenerDisponibilidadActivaOperarios({ prisma, operariosIds, fecha }),
    obtenerHorariosEfectivosOperarios({ prisma, conjuntoId, operariosIds, dia }),
  ]);
  const byId = new Map(operarios.map((operario) => [operario.id, operario]));
  const operariosSinConfiguracion = operariosIds.filter((id) => !byId.has(id));

  let intervalosConjunto: IntervaloLaboral[] = [];
  let intervalosEfectivos: IntervaloLaboral[] | null = null;

  for (const operarioId of operariosIds) {
    const operario = byId.get(operarioId);
    if (!operario) {
      intervalosEfectivos = [];
      continue;
    }
    const horarioEfectivo = horariosEfectivos.get(operarioId) ?? null;
    intervalosConjunto = unionIntervals(
      intervalosConjunto,
      horarioEfectivo ? workIntervalsFromHorario(horarioEfectivo) : [],
    );

    const periodo = disponibilidad.get(operarioId);
    const permitidos = allowedIntervalsForUserWithAvailability({
      dia,
      // `horario` no se usa cuando horarioEfectivo viene explícito (siempre
      // aquí); se pasa el mismo valor por completar el tipo requerido.
      horario: horarioEfectivo ?? { startMin: 0, endMin: 0 },
      horarioEfectivo,
      jornadaLaboral: operario.usuario?.jornadaLaboral ?? null,
      patronJornada: operario.usuario?.patronJornada ?? null,
      disponibilidad: periodo
        ? {
            trabajaDomingo: periodo.trabajaDomingo,
            diaDescanso: periodo.diaDescanso,
          }
        : null,
    });
    intervalosEfectivos =
      intervalosEfectivos == null ? permitidos : intersectIntervals(intervalosEfectivos, permitidos);
    if (!intervalosEfectivos.length) break;
  }

  return {
    dia,
    horario: horarioGeneral,
    intervalosConjunto,
    intervalosEfectivos: intervalosEfectivos ?? [],
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
  // `intervalosConjunto` ya contempla el horario de una plaza con horario
  // especial (puede tener ventana un día en que el conjunto no opera), así
  // que el rechazo se basa en la ventana de búsqueda real, no solo en si el
  // conjunto tiene fila ese día.
  if (!disponibilidad.intervalosConjunto.length) {
    return {
      ok: false,
      motivo: "SIN_HORARIO_CONJUNTO",
      mensaje: "Ni el conjunto ni los operarios asignados tienen un horario laboral válido para ese día.",
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
