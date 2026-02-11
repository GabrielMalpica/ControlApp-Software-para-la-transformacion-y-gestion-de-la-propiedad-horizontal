// src/utils/schedulerUtils.ts
import {
  PrismaClient,
  DiaSemana,
  TipoTarea,
  Frecuencia,
  EstadoTarea,
} from "../generated/prisma";
import { HorarioDia } from "./agenda";

export type Intervalo = { i: number; f: number }; // minutos dentro del día [0..1440]
export type Bloqueo = { startMin: number; endMin: number; reason?: string };
type BloquePlan = { i: number; f: number };
export type HHmm = `${string}:${string}`;

/* =======================================================
   Básicos de fecha / tiempo
======================================================= */

export function toMin(hhmm: string): number {
  const [hh, mm] = hhmm.split(":").map(Number);
  return (hh || 0) * 60 + (mm || 0);
}

export function toMinOfDay(d: Date): number {
  return d.getHours() * 60 + d.getMinutes();
}

export function dateToDiaSemana(d: Date): DiaSemana {
  // getDay(): 0 DOMINGO ... 6 SABADO
  switch (d.getDay()) {
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
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function toDateAtMin(baseDay: Date, minOfDay: number): Date {
  return new Date(
    baseDay.getFullYear(),
    baseDay.getMonth(),
    baseDay.getDate(),
    Math.floor(minOfDay / 60),
    minOfDay % 60,
    0,
    0,
  );
}

function clamp(min: number, v: number, max: number) {
  return Math.max(min, Math.min(v, max));
}

/* =======================================================
   Intervalos (merge / libres / intersección)
======================================================= */

export function normalizarIntervalos(items: Intervalo[]): Intervalo[] {
  if (!items.length) return [];
  const sorted = [...items].sort((x, y) => x.i - y.i);
  const res: Intervalo[] = [{ ...sorted[0] }];
  for (let k = 1; k < sorted.length; k++) {
    const last = res[res.length - 1];
    const cur = sorted[k];
    if (cur.i <= last.f) last.f = Math.max(last.f, cur.f);
    else res.push({ ...cur });
  }
  return res;
}

export function mergeIntervalos(xs: Intervalo[]): Intervalo[] {
  return normalizarIntervalos(xs);
}

export function freeFromOccupied(
  startMin: number,
  endMin: number,
  ocupados: Intervalo[],
): Intervalo[] {
  const occ = mergeIntervalos(
    ocupados
      .map((x) => ({ i: Math.max(startMin, x.i), f: Math.min(endMin, x.f) }))
      .filter((x) => x.f > x.i),
  );

  const libres: Intervalo[] = [];
  let cur = startMin;

  for (const o of occ) {
    if (o.i > cur) libres.push({ i: cur, f: o.i });
    cur = Math.max(cur, o.f);
  }
  if (cur < endMin) libres.push({ i: cur, f: endMin });

  return libres;
}

function intersect(a: Intervalo[], b: Intervalo[]): Intervalo[] {
  const out: Intervalo[] = [];
  let i = 0,
    j = 0;
  while (i < a.length && j < b.length) {
    const s = Math.max(a[i].i, b[j].i);
    const e = Math.min(a[i].f, b[j].f);
    if (e > s) out.push({ i: s, f: e });
    if (a[i].f < b[j].f) i++;
    else j++;
  }
  return out;
}

/* =======================================================
   Festivos y horarios
======================================================= */

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
    // solo si está dentro del horario y bien ordenado
    if (startMin < di && di < df && df < endMin) {
      descanso = { startMin: di, endMin: df };
    }
  }

  return { startMin, endMin, descanso };
}

export function getBloqueosPorDescanso(
  horario: { descanso?: { startMin: number; endMin: number } } | null,
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

export function siguienteDiaHabil(params: {
  fecha: Date;
  festivosSet: Set<string>;
  horariosPorDia: Map<DiaSemana, any>;
}): Date | null {
  const { fecha, festivosSet, horariosPorDia } = params;
  const x = new Date(
    fecha.getFullYear(),
    fecha.getMonth(),
    fecha.getDate(),
    0,
    0,
    0,
    0,
  );

  for (let guard = 0; guard < 31; guard++) {
    x.setDate(x.getDate() + 1);
    const key = ymdLocal(x);
    const ds = dateToDiaSemana(x);
    if (!festivosSet.has(key) && horariosPorDia.has(ds)) return new Date(x);
  }
  return null;
}

/* =======================================================
   Agenda por operario
======================================================= */

/**
 * Construye la agenda por operario para un día, incluyendo:
 * - tareas existentes (borrador opcional)
 * - bloqueos globales (ej: descanso)
 * - opcional: excluir estados que NO deben bloquear
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
    0,
  );
  const fin = new Date(
    fechaDia.getFullYear(),
    fechaDia.getMonth(),
    fechaDia.getDate(),
    23,
    59,
    59,
    999,
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

  for (const t of tareas) {
    // clamp seguro al día actual
    const start = t.fechaInicio < ini ? ini : t.fechaInicio;
    const end = t.fechaFin > fin ? fin : t.fechaFin;

    let i = clamp(0, toMinOfDay(start), 1440);
    let f = clamp(0, toMinOfDay(end), 1440);

    // si por alguna razón queda invertido, lo ignoramos
    if (f <= i) continue;

    for (const op of t.operarios) {
      if (agenda[op.id]) agenda[op.id].push({ i, f });
    }
  }

  if (bloqueosGlobales.length) {
    for (const opId of operariosIds) {
      for (const b of bloqueosGlobales) {
        agenda[opId].push({ i: b.startMin, f: b.endMin });
      }
    }
  }

  for (const opId of Object.keys(agenda)) {
    agenda[opId] = normalizarIntervalos(agenda[opId]);
  }

  return agenda;
}

/* =======================================================
   Búsqueda de huecos (earliest / split)
======================================================= */

/**
 * Primer hueco posible donde TODOS los operarios están libres.
 * Usa agenda por operario (no “ocupados globales”).
 */
export function buscarHuecoDiaEarliest(params: {
  startMin: number;
  endMin: number;
  durMin: number;
  operariosIds: string[];
  agendaPorOperario: Record<string, Intervalo[]>;
  desiredStartMin?: number;
}): number | null {
  const { startMin, endMin, durMin, operariosIds, agendaPorOperario } = params;
  const desired = Math.max(startMin, params.desiredStartMin ?? startMin);

  let libresComunes: Intervalo[] | null = null;

  for (const opId of operariosIds) {
    const ocup = agendaPorOperario[opId] ?? [];
    const libres = freeFromOccupied(startMin, endMin, ocup);
    libresComunes =
      libresComunes == null ? libres : intersect(libresComunes, libres);
    if (!libresComunes.length) return null;
  }

  for (const L of libresComunes!) {
    const s = Math.max(L.i, desired);
    if (L.f - s >= durMin) return s;
  }
  return null;
}

/**
 * ✅ Hueco earliest desde apertura, permitiendo:
 * - 1 bloque (ideal)
 * - 2 bloques (split) para rodear descanso (ej: 12:30-13:00 + 14:00-15:10)
 *
 * Se trabaja con "ocupados globales" ya merged + bloqueos por descanso.
 */
export function buscarHuecoDiaConSplitEarliest(params: {
  startMin: number;
  endMin: number;
  durMin: number;
  ocupados: Intervalo[];
  bloqueos: Bloqueo[];
  desiredStartMin?: number;
  maxBloques?: 1 | 2;
}): BloquePlan[] | null {
  const {
    startMin,
    endMin,
    durMin,
    ocupados,
    bloqueos,
    desiredStartMin = startMin,
    maxBloques = 2,
  } = params;

  const blocked = mergeIntervalos([
    ...ocupados,
    ...bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
  ]);

  const libres = freeFromOccupied(startMin, endMin, blocked);

  // 1) 1 bloque earliest
  for (const L of libres) {
    const s = Math.max(L.i, desiredStartMin);
    if (L.f - s >= durMin) return [{ i: s, f: s + durMin }];
  }

  if (maxBloques < 2) return null;

  // 2) split en 2 bloques earliest
  for (let idx = 0; idx < libres.length; idx++) {
    const L1 = libres[idx];
    const s1 = Math.max(L1.i, desiredStartMin);
    const cap1 = L1.f - s1;
    if (cap1 <= 0) continue;

    const take1 = Math.min(cap1, durMin);
    const rem = durMin - take1;

    if (rem <= 0) return [{ i: s1, f: s1 + durMin }];

    for (let j = idx + 1; j < libres.length; j++) {
      const L2 = libres[j];
      const cap2 = L2.f - L2.i;
      if (cap2 >= rem) {
        return [
          { i: s1, f: s1 + take1 },
          { i: L2.i, f: L2.i + rem },
        ];
      }
    }
  }

  return null;
}

/* =======================================================
   Solapes + sugerencias
======================================================= */

export async function buscarSolapesEnConjunto(
  prisma: PrismaClient,
  params: {
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
    incluirBorrador?: boolean;
    excluirEstados?: string[];
  },
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
 * Sugerencia de “próximo hueco” en el día,
 * respetando jornada y descanso, y usando agenda de operarios.
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

  // si no hay operarios, igual respetamos descanso con agenda dummy
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
            bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
          ),
        };

  const ids = operariosIds.length ? operariosIds : ["__dummy__"];

  const inicioSugerido = buscarHuecoDiaEarliest({
    startMin: Math.max(desiredStartMin, startMin),
    endMin,
    durMin,
    operariosIds: ids,
    agendaPorOperario: agenda as any,
    desiredStartMin: Math.max(desiredStartMin, startMin),
  });

  if (inicioSugerido == null) return { ok: false, reason: "SIN_HUECO_DIA" };

  return {
    ok: true,
    startMin: inicioSugerido,
    endMin: inicioSugerido + durMin,
  };
}

export function solapa(a: Intervalo, b: Intervalo) {
  return a.i < b.f && b.i < a.f;
}

type CrearTareaPayload = {
  descripcion: string;
  tipo: TipoTarea;
  frecuencia?: Frecuencia | null;

  prioridad: number;
  supervisorId?: string | null;

  ubicacionId: number;
  elementoId: number;
  conjuntoId: string;

  borrador: boolean;
  periodoAnio?: number | null;
  periodoMes?: number | null;

  // planes
  insumosPlanJson?: any;
  maquinariaPlanJson?: any;
  herramientasPlanJson?: any;

  // operarios
  operariosIds: string[];

  // trazabilidad opcional (para “movida por festivo”)
  marcarComoReprogramada?: boolean;
  motivoReprogramacion?: string | null;
  fechaInicioOriginal?: Date | null;
  fechaFinOriginal?: Date | null;
  grupoPlanId?: string | null;
  bloqueIndexBase?: number; // ej: 5 => si split crea 5 y 6
  bloquesTotalesOverride?: number | null;
};

export async function intentarReemplazoPorPrioridadBaja(params: {
  prisma: PrismaClient;

  conjuntoId: string;
  fechaDia: Date;

  // jornada
  startMin: number;
  endMin: number;
  bloqueos: Bloqueo[];

  // nueva tarea
  durMin: number;
  payload: CrearTareaPayload;

  // agenda
  incluirBorradorEnAgenda: boolean;
  incluirPublicadasEnAgenda: boolean;

  // ✅ NUEVO: para reportar al UI / log
  onEvent?: (
    ev:
      | {
          tipo: "REEMPLAZO";
          nuevaTareaIds: number[];
          reprogramadasIds: number[];
        }
      | { tipo: "SIN_CANDIDATAS" }
      | { tipo: "SIN_HUECO" },
  ) => void;
}): Promise<
  | {
      ok: true;
      nuevaTareaIds: number[];
      reprogramadasIds: number[];
      bloques: Intervalo[];
    }
  | { ok: false; reason: "SIN_HUECO" | "SIN_CANDIDATAS" }
> {
  const {
    prisma,
    conjuntoId,
    fechaDia,
    startMin,
    endMin,
    bloqueos,
    durMin,
    payload,
    incluirBorradorEnAgenda,
    onEvent,
  } = params;

  const operariosIds = payload.operariosIds ?? [];

  // 1) agenda actual del día
  const agenda = operariosIds.length
    ? await buildAgendaPorOperarioDia({
        prisma,
        conjuntoId,
        fechaDia,
        operariosIds,
        incluirBorrador: incluirBorradorEnAgenda,
        bloqueosGlobales: bloqueos,
        excluirEstados: ["PENDIENTE_REPROGRAMACION"],
      })
    : null;

  let ocupadosGlobal: Intervalo[] = [];
  if (agenda) {
    const all: Intervalo[] = [];
    for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
    ocupadosGlobal = mergeIntervalos(all);
  } else {
    ocupadosGlobal = mergeIntervalos(
      bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
    );
  }

  // 2) intento normal primero (por si sí cabe)
  const normal = buscarHuecoDiaConSplitEarliest({
    startMin,
    endMin,
    durMin,
    ocupados: ocupadosGlobal,
    bloqueos,
    desiredStartMin: startMin,
    maxBloques: 2,
  });

  if (normal) {
    const ids = await crearTareaConBloques(
      prisma,
      fechaDia,
      normal,
      durMin,
      payload,
    );

    // ✅ evento: no hubo reemplazo (reprogramadas vacío)
    onEvent?.({ tipo: "REEMPLAZO", nuevaTareaIds: ids, reprogramadasIds: [] });

    return {
      ok: true,
      nuevaTareaIds: ids,
      reprogramadasIds: [],
      bloques: normal,
    };
  }

  // 3) buscar candidatas del día (prioridad 2–3) para reemplazo
  const ini = new Date(
    fechaDia.getFullYear(),
    fechaDia.getMonth(),
    fechaDia.getDate(),
    0,
    0,
    0,
    0,
  );
  const fin = new Date(
    fechaDia.getFullYear(),
    fechaDia.getMonth(),
    fechaDia.getDate(),
    23,
    59,
    59,
    999,
  );

  const candidatas = await prisma.tarea.findMany({
    where: {
      conjuntoId,
      fechaInicio: { lte: fin },
      fechaFin: { gte: ini },
      estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
      prioridad: { in: [2, 3] },
    },
    select: {
      id: true,
      prioridad: true,
      fechaInicio: true,
      fechaFin: true,
      grupoPlanId: true,
      bloqueIndex: true,
      bloquesTotales: true,
    },
    orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }], // primero 3, luego 2
  });

  if (!candidatas.length) {
    onEvent?.({ tipo: "SIN_CANDIDATAS" });
    return { ok: false, reason: "SIN_CANDIDATAS" };
  }

  // helper: ids a excluir (si está en grupo -> todo el grupo)
  const excluyeIds = async (t: (typeof candidatas)[number]) => {
    if (!t.grupoPlanId) return new Set([t.id]);

    const grupo = await prisma.tarea.findMany({
      where: { grupoPlanId: t.grupoPlanId },
      select: { id: true },
    });
    return new Set(grupo.map((x) => x.id));
  };

  // 4) probar reemplazos
  for (const cand of candidatas) {
    const idsAExcluir = await excluyeIds(cand);

    // reconstruir ocupadosGlobal sin esos ids
    let ocupSinCand: Intervalo[] = [];

    if (operariosIds.length) {
      const tareasDia = await prisma.tarea.findMany({
        where: {
          conjuntoId,
          fechaInicio: { lte: fin },
          fechaFin: { gte: ini },
          id: { notIn: Array.from(idsAExcluir) },
          estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
          operarios: { some: { id: { in: operariosIds } } },
        },
        select: { fechaInicio: true, fechaFin: true },
      });

      const all: Intervalo[] = [];
      for (const t of tareasDia) {
        all.push({
          i: toMinOfDaySafe(t.fechaInicio),
          f: toMinOfDaySafe(t.fechaFin),
        });
      }
      for (const b of bloqueos) all.push({ i: b.startMin, f: b.endMin });

      ocupSinCand = mergeIntervalos(all);
    } else {
      const tareasDia = await prisma.tarea.findMany({
        where: {
          conjuntoId,
          fechaInicio: { lte: fin },
          fechaFin: { gte: ini },
          id: { notIn: Array.from(idsAExcluir) },
          estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        },
        select: { fechaInicio: true, fechaFin: true },
      });

      const all: Intervalo[] = tareasDia.map((t) => ({
        i: toMinOfDaySafe(t.fechaInicio),
        f: toMinOfDaySafe(t.fechaFin),
      }));
      for (const b of bloqueos) all.push({ i: b.startMin, f: b.endMin });

      ocupSinCand = mergeIntervalos(all);
    }

    const bloques = buscarHuecoDiaConSplitEarliest({
      startMin,
      endMin,
      durMin,
      ocupados: ocupSinCand,
      bloqueos,
      desiredStartMin: startMin,
      maxBloques: 2,
    });

    if (!bloques) continue;

    // 5) ejecutar reemplazo real en transacción
    const now = new Date();
    const motivo =
      payload.motivoReprogramacion ??
      "Reprogramada por reemplazo de prioridad alta";

    const result = await prisma.$transaction(async (tx) => {
      const reprogramadas = Array.from(idsAExcluir);

      for (const id of reprogramadas) {
        const t = await tx.tarea.findUnique({
          where: { id },
          select: {
            id: true,
            fechaInicioOriginal: true,
            fechaFinOriginal: true,
            fechaInicio: true,
            fechaFin: true,
          },
        });
        if (!t) continue;

        await tx.tarea.update({
          where: { id },
          data: {
            estado: "PENDIENTE_REPROGRAMACION" as any,
            reprogramada: true,
            reprogramadaEn: now,
            reprogramadaMotivo: motivo,
            fechaInicioOriginal: t.fechaInicioOriginal ?? t.fechaInicio,
            fechaFinOriginal: t.fechaFinOriginal ?? t.fechaFin,
          },
        });
      }

      const nuevaIds = await crearTareaConBloques(
        tx as any,
        fechaDia,
        bloques,
        durMin,
        payload,
      );

      const nuevaRefId = nuevaIds[0] ?? null;
      if (nuevaRefId) {
        await tx.tarea.updateMany({
          where: { id: { in: reprogramadas } },
          data: { reprogramadaPorTareaId: nuevaRefId },
        });
      }

      return { nuevaIds, reprogramadas };
    });

    onEvent?.({
      tipo: "REEMPLAZO",
      nuevaTareaIds: result.nuevaIds,
      reprogramadasIds: result.reprogramadas,
    });

    return {
      ok: true,
      nuevaTareaIds: result.nuevaIds,
      reprogramadasIds: result.reprogramadas,
      bloques,
    };
  }

  onEvent?.({ tipo: "SIN_HUECO" });
  return { ok: false, reason: "SIN_HUECO" };
}

// ---- helpers ----

export function toMinOfDaySafe(d: Date): number {
  const dd = new Date(d);
  const h = dd.getHours();
  const m = dd.getMinutes();
  const min = h * 60 + m;

  if (!Number.isFinite(min)) return 0;
  return Math.max(0, Math.min(24 * 60, min));
}

async function crearTareaConBloques(
  prisma: PrismaClient,
  fechaDia: Date,
  bloques: Intervalo[],
  durMinTotal: number,
  payload: CrearTareaPayload,
): Promise<number[]> {
  const ids: number[] = [];

  // si split: cada bloque tiene su dur real
  const grupoPlanId =
    payload.grupoPlanId ??
    (bloques.length > 1
      ? `RP-${ymdLocal(fechaDia)}-${Math.random().toString(36).slice(2, 8)}`
      : null);

  let idx = payload.bloqueIndexBase ?? 1;

  for (const b of bloques) {
    const fechaInicio = toDateAtMin(fechaDia, b.i);
    const fechaFin = toDateAtMin(fechaDia, b.f);
    const dur = Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000));

    const created = await prisma.tarea.create({
      data: {
        descripcion: payload.descripcion,
        tipo: payload.tipo,
        frecuencia: payload.frecuencia ?? null,

        fechaInicio,
        fechaFin,
        duracionMinutos: dur,
        prioridad: payload.prioridad,
        estado: EstadoTarea.ASIGNADA,

        conjuntoId: payload.conjuntoId,
        ubicacionId: payload.ubicacionId,
        elementoId: payload.elementoId,
        supervisorId: payload.supervisorId ?? null,

        borrador: payload.borrador,
        periodoAnio: payload.periodoAnio ?? null,
        periodoMes: payload.periodoMes ?? null,

        grupoPlanId,
        bloqueIndex: grupoPlanId ? idx : null,
        bloquesTotales: grupoPlanId
          ? (payload.bloquesTotalesOverride ?? bloques.length)
          : null,

        tiempoEstimadoMinutos: dur,

        insumosPlanJson: payload.insumosPlanJson ?? undefined,
        maquinariaPlanJson: payload.maquinariaPlanJson ?? undefined,
        herramientasPlanJson: payload.herramientasPlanJson ?? undefined,

        reprogramada: payload.marcarComoReprogramada ?? false,
        reprogramadaEn: payload.marcarComoReprogramada ? new Date() : null,
        reprogramadaMotivo: payload.marcarComoReprogramada
          ? (payload.motivoReprogramacion ?? null)
          : null,
        fechaInicioOriginal: payload.marcarComoReprogramada
          ? (payload.fechaInicioOriginal ?? null)
          : null,
        fechaFinOriginal: payload.marcarComoReprogramada
          ? (payload.fechaFinOriginal ?? null)
          : null,

        operarios: payload.operariosIds.length
          ? { connect: payload.operariosIds.map((id) => ({ id })) }
          : undefined,
      },
      select: { id: true },
    });

    ids.push(created.id);
    idx++;
  }

  return ids;
}

export function splitMinutes(totalMin: number, days: number): number[] {
  const d = Math.max(1, Math.floor(days));
  const t = Math.max(1, Math.floor(totalMin));

  const base = Math.floor(t / d);
  const rem = t % d;

  const out: number[] = [];
  for (let i = 0; i < d; i++) out.push(base + (i < rem ? 1 : 0));
  return out.filter((x) => x > 0);
}

export function findNextValidDay(params: {
  start: Date;
  periodoAnio: number;
  periodoMes: number;
  prioridad: number;
  horariosPorDia: Map<DiaSemana, any>;
  festivosSet: Set<string>;
}): Date | null {
  const {
    start,
    periodoAnio,
    periodoMes,
    prioridad,
    horariosPorDia,
    festivosSet,
  } = params;

  const cur = new Date(
    start.getFullYear(),
    start.getMonth(),
    start.getDate(),
    0,
    0,
    0,
    0,
  );

  // buscamos dentro del mes
  for (let guard = 0; guard < 40; guard++) {
    // si nos salimos del mes, aborta
    if (
      cur.getFullYear() !== periodoAnio ||
      cur.getMonth() + 1 !== periodoMes
    ) {
      return null;
    }

    const ds = dateToDiaSemana(cur);
    const tieneHorario = horariosPorDia.has(ds);
    if (!tieneHorario) {
      cur.setDate(cur.getDate() + 1);
      continue;
    }

    const esFestivo = festivosSet.has(ymdLocal(cur));

    // ✅ REGLA:
    // - prioridad 1: si cae en festivo, SE MUEVE al siguiente día hábil (no se programa en festivo)
    // - prioridad 2-3: si cae en festivo, NO se crea (se omite)
    if (esFestivo) {
      if (prioridad === 1) {
        cur.setDate(cur.getDate() + 1);
        continue; // sigue buscando el próximo día hábil con horario
      }
      return null; // prioridad 2-3: se omite
    }

    return new Date(cur);
  }

  return null;
}

async function buildBloqueosPorPatronJornada(params: {
  prisma: PrismaClient;
  fechaDia: Date;
  horarioDia: HorarioDia;
  operariosIds: string[];
}): Promise<Bloqueo[]> {
  const { prisma, fechaDia, horarioDia, operariosIds } = params;
  if (!operariosIds.length) return [];

  const dia = dateToDiaSemana(fechaDia);

  // Traer jornada y patrón desde Usuario
  const ops = await prisma.operario.findMany({
    where: { id: { in: operariosIds.map(String) } },
    select: {
      id: true,
      usuario: {
        select: {
          jornadaLaboral: true,
          patronJornada: true,
        },
      },
    },
  });

  const bloqueos: Bloqueo[] = [];

  for (const op of ops) {
    const jornada = (op.usuario?.jornadaLaboral ?? null) as string | null;
    const patron = (op.usuario?.patronJornada ?? null) as string | null;

    // COMPLETA => no bloquea nada
    if (jornada === "COMPLETA") continue;

    // Si no tiene jornada, por seguridad no limitamos (o si prefieres, bloquea todo)
    if (!jornada) continue;

    // MEDIO_TIEMPO sin patrón => no debería poder trabajar (bloquea todo el horario)
    const allowed = allowedIntervalsForUser({
      dia,
      horario: horarioDia,
      jornadaLaboral: jornada,
      patronJornada: patron,
    });

    const b = bloqueosFromAllowed({
      horario: horarioDia,
      allowed,
      reason: `PATRON_${op.id}`,
    });

    bloqueos.push(...b);
  }

  return bloqueos;
}

function allowedIntervalsForUser(params: {
  dia: DiaSemana;
  horario: HorarioDia;
  jornadaLaboral: string | null;
  patronJornada: string | null;
}): Array<{ i: number; f: number }> {
  const { dia, horario, jornadaLaboral, patronJornada } = params;

  if (!jornadaLaboral) return [{ i: horario.startMin, f: horario.endMin }];

  if (jornadaLaboral === "COMPLETA") {
    return [{ i: horario.startMin, f: horario.endMin }];
  }

  if (jornadaLaboral !== "MEDIO_TIEMPO") {
    return [{ i: horario.startMin, f: horario.endMin }];
  }

  if (!patronJornada) return [];

  const apertura = horario.startMin;
  const cierre = horario.endMin;

  const clamp = (i: number, f: number) => {
    const ii = Math.max(i, apertura);
    const ff = Math.min(f, cierre);
    return ff > ii ? { i: ii, f: ff } : null;
  };

  // 13:00 - 16:00
  const m13 = 13 * 60;
  const m16 = 16 * 60;

  switch (patronJornada) {
    case "MEDIO_DIAS_INTERCALADOS": {
      if (dia === DiaSemana.LUNES || dia === DiaSemana.MIERCOLES) {
        return [{ i: apertura, f: cierre }];
      }
      if (dia === DiaSemana.VIERNES) {
        const x = clamp(apertura, apertura + 6 * 60);
        return x ? [x] : [];
      }
      return [];
    }

    case "MEDIO_SEMANA_SABADO": {
      if (
        dia === DiaSemana.LUNES ||
        dia === DiaSemana.MARTES ||
        dia === DiaSemana.MIERCOLES ||
        dia === DiaSemana.JUEVES ||
        dia === DiaSemana.VIERNES
      ) {
        const x = clamp(apertura, apertura + 4 * 60);
        return x ? [x] : [];
      }
      if (dia === DiaSemana.SABADO) {
        const x = clamp(apertura, apertura + 2 * 60); // 8am-10am (según tu corrección)
        return x ? [x] : [];
      }
      return [];
    }

    case "MEDIO_SEMANA_SABADO_TARDE": {
      if (
        dia === DiaSemana.LUNES ||
        dia === DiaSemana.MARTES ||
        dia === DiaSemana.MIERCOLES ||
        dia === DiaSemana.JUEVES ||
        dia === DiaSemana.VIERNES
      ) {
        const x = clamp(m13, m16);
        return x ? [x] : [];
      }
      if (dia === DiaSemana.SABADO) {
        const x = clamp(apertura, apertura + 2 * 60);
        return x ? [x] : [];
      }
      return [];
    }

    default:
      return [];
  }
}

function bloqueosFromAllowed(params: {
  horario: HorarioDia;
  allowed: Array<{ i: number; f: number }>;
  reason: string;
}): Bloqueo[] {
  const { horario, allowed, reason } = params;

  if (!allowed.length) {
    return [{ startMin: horario.startMin, endMin: horario.endMin, reason }];
  }

  // En tus patrones siempre queda un único intervalo permitido por día
  const a = allowed[0];

  const out: Bloqueo[] = [];
  if (horario.startMin < a.i) {
    out.push({ startMin: horario.startMin, endMin: a.i, reason });
  }
  if (a.f < horario.endMin) {
    out.push({ startMin: a.f, endMin: horario.endMin, reason });
  }
  return out;
}
