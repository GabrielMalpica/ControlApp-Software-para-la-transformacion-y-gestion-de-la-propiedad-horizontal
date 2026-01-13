// src/utils/schedulerUtils.ts
import { PrismaClient, TipoTarea, DiaSemana } from "../generated/prisma";

export type Intervalo = { i: number; f: number }; // minutos dentro del día
export type Bloqueo = { startMin: number; endMin: number; reason?: string };

export function toMin(hhmm: string): number {
  const [hh, mm] = hhmm.split(":").map(Number);
  return (hh || 0) * 60 + (mm || 0);
}

export function toMinOfDay(d: Date): number {
  return d.getHours() * 60 + d.getMinutes();
}

export function dateToDiaSemana(d: Date): DiaSemana {
  // Ajusta si tu enum Prisma es distinto.
  // Esto asume: LUNES..DOMINGO
  const weekday = d.getDay(); // 0 domingo ... 6 sábado
  switch (weekday) {
    case 1:
      return "LUNES" as DiaSemana;
    case 2:
      return "MARTES" as DiaSemana;
    case 3:
      return "MIERCOLES" as DiaSemana;
    case 4:
      return "JUEVES" as DiaSemana;
    case 5:
      return "VIERNES" as DiaSemana;
    case 6:
      return "SABADO" as DiaSemana;
    default:
      return "DOMINGO" as DiaSemana;
  }
}

export function ymdLocal(d: Date): string {
  const x = new Date(d);
  const y = x.getFullYear();
  const m = String(x.getMonth() + 1).padStart(2, "0");
  const day = String(x.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function solapa(a: Intervalo, b: Intervalo): boolean {
  return a.i < b.f && a.f > b.i;
}

export function normalizarIntervalos(items: Intervalo[]): Intervalo[] {
  if (!items.length) return [];
  const sorted = [...items].sort((x, y) => x.i - y.i);
  const res: Intervalo[] = [sorted[0]];
  for (let k = 1; k < sorted.length; k++) {
    const last = res[res.length - 1];
    const cur = sorted[k];
    if (cur.i <= last.f) last.f = Math.max(last.f, cur.f);
    else res.push({ ...cur });
  }
  return res;
}

export async function getFestivosSet(params: {
  prisma: PrismaClient;
  pais: string;
  inicio: Date;
  fin: Date;
}): Promise<Set<string>> {
  const { prisma, pais, inicio, fin } = params;

  const festivos = await prisma.festivo.findMany({
    where: {
      pais,
      fecha: { gte: inicio, lte: fin },
    },
    select: { fecha: true },
  });

  return new Set(festivos.map((f) => ymdLocal(f.fecha)));
}

export async function getHorarioConDescansoDia(params: {
  prisma: PrismaClient;
  conjuntoId: string;
  fechaDia: Date;
}): Promise<{
  startMin: number;
  endMin: number;
  descanso?: { startMin: number; endMin: number };
} | null> {
  const { prisma, conjuntoId, fechaDia } = params;
  const dia = dateToDiaSemana(fechaDia);

  const h = await prisma.conjuntoHorario.findUnique({
    where: { conjuntoId_dia: { conjuntoId, dia } },
    select: {
      horaApertura: true,
      horaCierre: true,
      descansoInicio: true,
      descansoFin: true,
    },
  });

  if (!h) return null;

  const startMin = toMin(h.horaApertura);
  const endMin = toMin(h.horaCierre);

  let descanso: { startMin: number; endMin: number } | undefined;
  if (h.descansoInicio && h.descansoFin) {
    const di = toMin(h.descansoInicio);
    const df = toMin(h.descansoFin);
    // seguridad: solo si está dentro y bien ordenado
    if (startMin < di && di < df && df < endMin) {
      descanso = { startMin: di, endMin: df };
    }
  }

  return { startMin, endMin, descanso };
}

export function getBloqueosPorDescanso(
  horario: { descanso?: { startMin: number; endMin: number } } | null
): Bloqueo[] {
  if (!horario?.descanso) return [];
  return [
    {
      startMin: horario.descanso.startMin,
      endMin: horario.descanso.endMin,
      reason: "DESCANSO",
    },
  ];
}

/**
 * Construye la agenda por operario para un día, incluyendo:
 * - tareas existentes (borrador opcional)
 * - bloqueos globales (ej: descanso)
 * - opcional: excluir estados que NO deben bloquear (ej: REPROGRAMADA)
 */
export async function buildAgendaPorOperarioDia(params: {
  prisma: PrismaClient;
  conjuntoId: string;
  fechaDia: Date;
  operariosIds: string[];
  incluirBorrador: boolean;
  bloqueosGlobales?: Bloqueo[];
  excluirEstados?: string[];
}): Promise<Record<string, Intervalo[]>> {
  const {
    prisma,
    conjuntoId,
    fechaDia,
    operariosIds,
    incluirBorrador,
    bloqueosGlobales = [],
    excluirEstados = [],
  } = params;

  const ini = new Date(
    fechaDia.getFullYear(),
    fechaDia.getMonth(),
    fechaDia.getDate(),
    0,
    0,
    0,
    0
  );
  const fin = new Date(
    fechaDia.getFullYear(),
    fechaDia.getMonth(),
    fechaDia.getDate(),
    23,
    59,
    59,
    999
  );

  const tareas = await prisma.tarea.findMany({
    where: {
      conjuntoId,
      fechaInicio: { lte: fin },
      fechaFin: { gte: ini },
      ...(incluirBorrador ? {} : { borrador: false }),
      ...(excluirEstados.length
        ? { estado: { notIn: excluirEstados as any } }
        : {}),
      operarios: { some: { id: { in: operariosIds } } },
    },
    select: {
      fechaInicio: true,
      fechaFin: true,
      operarios: { select: { id: true } },
    },
  });

  const agenda: Record<string, Intervalo[]> = {};
  for (const opId of operariosIds) agenda[opId] = [];

  // tareas
  for (const t of tareas) {
    const i = toMinOfDay(t.fechaInicio);
    const f = toMinOfDay(t.fechaFin);
    for (const op of t.operarios) {
      if (agenda[op.id]) agenda[op.id].push({ i, f });
    }
  }

  // bloqueos globales (ej descanso)
  if (bloqueosGlobales.length) {
    for (const opId of operariosIds) {
      for (const b of bloqueosGlobales) {
        agenda[opId].push({ i: b.startMin, f: b.endMin });
      }
    }
  }

  // normaliza (merge solapes)
  for (const opId of Object.keys(agenda)) {
    agenda[opId] = normalizarIntervalos(agenda[opId]);
  }

  return agenda;
}

/**
 * Busca hueco minuto a minuto.
 * Si quieres hacerlo por bloques de 5 min, cambia cursor += 5
 */
export function buscarHuecoDia(params: {
  startMin: number;
  endMin: number;
  durMin: number;
  operariosIds: string[];
  agendaPorOperario: Record<string, Intervalo[]>;
}): number | null {
  const { startMin, endMin, durMin, operariosIds, agendaPorOperario } = params;
  const ultimoInicio = endMin - durMin;

  for (let cursor = startMin; cursor <= ultimoInicio; cursor += 1) {
    const candidato = { i: cursor, f: cursor + durMin };

    let ok = true;
    for (const opId of operariosIds) {
      const ocupados = agendaPorOperario[opId] ?? [];
      if (ocupados.some((o) => solapa(o, candidato))) {
        ok = false;
        break;
      }
    }
    if (ok) return cursor;
  }
  return null;
}

export async function buscarSolapesEnConjunto(
  prisma: PrismaClient,
  params: {
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
    incluirBorrador?: boolean;
    excluirEstados?: string[];
  }
) {
  const {
    conjuntoId,
    fechaInicio,
    fechaFin,
    incluirBorrador = true,
    excluirEstados = [],
  } = params;

  return prisma.tarea.findMany({
    where: {
      conjuntoId,
      fechaInicio: { lt: fechaFin },
      fechaFin: { gt: fechaInicio },
      ...(incluirBorrador ? {} : { borrador: false }),
      ...(excluirEstados.length
        ? { estado: { notIn: excluirEstados as any } }
        : {}),
    },
    select: {
      id: true,
      descripcion: true,
      tipo: true,
      prioridad: true,
      estado: true,
      borrador: true,
      fechaInicio: true,
      fechaFin: true,
      ubicacionId: true,
      elementoId: true,
    },
    orderBy: [{ fechaInicio: "asc" }],
  });
}

/**
 * Sugerencia de “próximo hueco” en el día, respetando jornada y descanso,
 * y usando agenda de operarios (si hay operarios).
 */
export async function sugerirHuecoDia(params: {
  prisma: PrismaClient;
  conjuntoId: string;
  fechaDia: Date;
  desiredStartMin: number;
  durMin: number;
  operariosIds: string[];
  incluirBorradorAgenda?: boolean;
  excluirEstadosAgenda?: string[];
}): Promise<
  { ok: true; startMin: number; endMin: number } | { ok: false; reason: string }
> {
  const {
    prisma,
    conjuntoId,
    fechaDia,
    desiredStartMin,
    durMin,
    operariosIds,
    incluirBorradorAgenda = true,
    excluirEstadosAgenda = [],
  } = params;

  const horario = await getHorarioConDescansoDia({
    prisma,
    conjuntoId,
    fechaDia,
  });
  if (!horario) return { ok: false, reason: "DIA_SIN_HORARIO" };

  const { startMin, endMin } = horario;
  const bloqueos = getBloqueosPorDescanso(horario);

  // si no hay operarios, igual respetamos descanso con un “agenda dummy”
  const agenda =
    operariosIds.length > 0
      ? await buildAgendaPorOperarioDia({
          prisma,
          conjuntoId,
          fechaDia,
          operariosIds,
          incluirBorrador: incluirBorradorAgenda,
          bloqueosGlobales: bloqueos,
          excluirEstados: excluirEstadosAgenda,
        })
      : {
          __dummy__: normalizarIntervalos(
            bloqueos.map((b) => ({ i: b.startMin, f: b.endMin }))
          ),
        };

  const ids = operariosIds.length ? operariosIds : ["__dummy__"];

  const inicioSugerido = buscarHuecoDia({
    startMin: Math.max(desiredStartMin, startMin),
    endMin,
    durMin,
    operariosIds: ids,
    agendaPorOperario: agenda as any,
  });

  if (inicioSugerido == null) return { ok: false, reason: "SIN_HUECO_DIA" };
  return {
    ok: true,
    startMin: inicioSugerido,
    endMin: inicioSugerido + durMin,
  };
}

export type HorarioDia = {
  startMin: number;
  endMin: number;
  descansoStartMin?: number;
  descansoEndMin?: number;
};
