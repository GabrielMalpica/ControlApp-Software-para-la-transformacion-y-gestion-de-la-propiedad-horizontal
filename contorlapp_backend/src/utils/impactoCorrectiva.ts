// Impacto de programar una correctiva (actividad especial) sobre la agenda
// publicada de sus operarios: qué tareas habría que reemplazar, cuáles lo
// impiden y qué huecos quedan. Lógica pura (sin base de datos): la usa la
// previsualización POST /gerente/tareas/reemplazo/impacto.

export type OperarioRef = { id: string; nombre: string };

export type TareaAgendaImpacto = {
  id: number;
  descripcion: string;
  tipo: string;
  estado: string;
  prioridad: number | null;
  fechaInicio: Date;
  fechaFin: Date;
  operarios: OperarioRef[];
};

export type TipoConfirmacionReemplazo = "AUTO" | "CONFIRM_WARN" | "CONFIRM_DANGER";
export type MotivoBloqueoReemplazo = "NO_ES_PREVENTIVA" | "PRIORIDAD" | "ESTADO";

/** Estados que ocupan la agenda de un operario (el resto ya no bloquea). */
export const ESTADOS_OCUPAN_AGENDA = ["ASIGNADA", "EN_PROCESO"] as const;
/** Una preventiva solo se reemplaza mientras no se haya cerrado. */
export const ESTADOS_REEMPLAZABLES = ["ASIGNADA", "EN_PROCESO"] as const;
/** Desde este tiempo libre seguido se avisa como "hueco grande". */
export const UMBRAL_HUECO_GRANDE_MIN = 60;

export function prioridadesReemplazables(prioridadCorrectiva: number): number[] {
  if (prioridadCorrectiva <= 1) return [1, 2, 3];
  if (prioridadCorrectiva === 2) return [2, 3];
  return [3];
}

export function tipoConfirmacionReemplazo(
  prioridadCorrectiva: number,
  prioridadPreventiva: number,
): TipoConfirmacionReemplazo | null {
  if (!prioridadesReemplazables(prioridadCorrectiva).includes(prioridadPreventiva)) {
    return null;
  }
  if (prioridadPreventiva === 3) return "AUTO";
  if (prioridadPreventiva === 2) return "CONFIRM_WARN";
  return "CONFIRM_DANGER";
}

export type TareaEnImpacto = {
  tareaId: number;
  descripcion: string;
  tipo: string;
  estado: string;
  prioridad: number;
  fechaInicio: Date;
  fechaFin: Date;
  duracionMinutos: number;
  /** Minutos que se cruzan con el horario de la actividad nueva. */
  minutosSolapados: number;
  operarios: Array<OperarioRef & { enLaActividad: boolean }>;
};

export type ReemplazoImpacto = TareaEnImpacto & {
  tipoConfirmacion: TipoConfirmacionReemplazo;
};

export type BloqueoImpacto = TareaEnImpacto & {
  motivo: MotivoBloqueoReemplazo;
  mensaje: string;
};

export type HuecoImpacto = {
  fechaInicio: Date;
  fechaFin: Date;
  minutos: number;
  grande: boolean;
};

export type OperarioImpacto = {
  operarioId: string;
  nombre: string;
  /** false: no está en la actividad, pero comparte una tarea que se reemplaza. */
  enLaActividad: boolean;
  reemplazadasIds: number[];
  bloqueosIds: number[];
  minutosReemplazados: number;
  /** Tiempo que le queda libre: lo reemplazado que la actividad no cubre. */
  huecos: HuecoImpacto[];
  minutosHueco: number;
  huecoGrande: boolean;
};

export type ImpactoCorrectiva = {
  /** Nadie tiene nada a esa hora: se crea sin reemplazar. */
  libre: boolean;
  /** No hay tareas que lo impidan (puede requerir reemplazos). */
  puedeProgramar: boolean;
  reemplazarIds: number[];
  reemplazos: ReemplazoImpacto[];
  bloqueos: BloqueoImpacto[];
  operarios: OperarioImpacto[];
  hayHuecoGrande: boolean;
  /** Prioridad más alta (número menor) entre las que se reemplazan. */
  prioridadMasAltaReemplazada: number | null;
};

type Tramo = { inicio: number; fin: number };

function unirTramos(tramos: Tramo[]): Tramo[] {
  const ordenados = tramos
    .filter((t) => t.fin > t.inicio)
    .sort((a, b) => a.inicio - b.inicio);
  const out: Tramo[] = [];
  for (const t of ordenados) {
    const ultimo = out[out.length - 1];
    if (ultimo && t.inicio <= ultimo.fin) {
      ultimo.fin = Math.max(ultimo.fin, t.fin);
    } else {
      out.push({ ...t });
    }
  }
  return out;
}

function restarTramos(base: Tramo[], quitar: Tramo[]): Tramo[] {
  let resto = unirTramos(base);
  for (const q of unirTramos(quitar)) {
    const siguiente: Tramo[] = [];
    for (const t of resto) {
      if (q.fin <= t.inicio || q.inicio >= t.fin) {
        siguiente.push(t);
        continue;
      }
      if (q.inicio > t.inicio) siguiente.push({ inicio: t.inicio, fin: q.inicio });
      if (q.fin < t.fin) siguiente.push({ inicio: q.fin, fin: t.fin });
    }
    resto = siguiente;
  }
  return resto;
}

const minutos = (ms: number) => Math.round(ms / 60000);

function hhmm(fecha: Date): string {
  return `${String(fecha.getHours()).padStart(2, "0")}:${String(fecha.getMinutes()).padStart(2, "0")}`;
}

function mensajeBloqueo(
  motivo: MotivoBloqueoReemplazo,
  tarea: TareaAgendaImpacto,
  prioridadCorrectiva: number,
): string {
  const ref = `"${tarea.descripcion}" (${hhmm(tarea.fechaInicio)}-${hhmm(tarea.fechaFin)})`;
  if (motivo === "NO_ES_PREVENTIVA") {
    return `${ref} ya es una actividad especial/correctiva y no se reemplaza. Muévela primero o elige otra hora.`;
  }
  if (motivo === "PRIORIDAD") {
    const permitidas = prioridadesReemplazables(prioridadCorrectiva)
      .map((p) => `P${p}`)
      .join(", ");
    return `${ref} es prioridad P${tarea.prioridad ?? 2}; una actividad P${prioridadCorrectiva} solo reemplaza preventivas ${permitidas}.`;
  }
  return `${ref} está en estado ${tarea.estado}; solo se reemplazan tareas asignadas o en proceso.`;
}

/**
 * Calcula el impacto de ubicar la actividad en [inicio, fin) para sus
 * operarios. [tareas] es la agenda publicada del día de esos operarios y de
 * quienes comparten tareas con ellos; las que ya no ocupan agenda se ignoran.
 */
export function calcularImpactoCorrectiva(params: {
  inicio: Date;
  fin: Date;
  prioridad: number;
  operarios: OperarioRef[];
  tareas: TareaAgendaImpacto[];
  umbralHuecoGrandeMin?: number;
}): ImpactoCorrectiva {
  const { inicio, fin, prioridad } = params;
  const umbral = params.umbralHuecoGrandeMin ?? UMBRAL_HUECO_GRANDE_MIN;
  const ini = inicio.getTime();
  const fi = fin.getTime();

  const enActividad = new Set(params.operarios.map((o) => String(o.id)));
  const nombres = new Map<string, string>();
  for (const o of params.operarios) nombres.set(String(o.id), o.nombre);

  const vistas = new Set<number>();
  const agenda = params.tareas.filter((t) => {
    if (vistas.has(t.id)) return false;
    vistas.add(t.id);
    return (ESTADOS_OCUPAN_AGENDA as readonly string[]).includes(String(t.estado));
  });
  for (const t of agenda) {
    for (const o of t.operarios) {
      if (!nombres.has(String(o.id))) nombres.set(String(o.id), o.nombre);
    }
  }

  const resumir = (t: TareaAgendaImpacto): TareaEnImpacto => {
    const solape = Math.min(fi, t.fechaFin.getTime()) - Math.max(ini, t.fechaInicio.getTime());
    return {
      tareaId: t.id,
      descripcion: t.descripcion,
      tipo: String(t.tipo),
      estado: String(t.estado),
      prioridad: t.prioridad ?? 2,
      fechaInicio: t.fechaInicio,
      fechaFin: t.fechaFin,
      duracionMinutos: Math.max(0, minutos(t.fechaFin.getTime() - t.fechaInicio.getTime())),
      minutosSolapados: Math.max(0, minutos(solape)),
      operarios: t.operarios.map((o) => ({
        id: String(o.id),
        nombre: o.nombre,
        enLaActividad: enActividad.has(String(o.id)),
      })),
    };
  };

  const reemplazos: ReemplazoImpacto[] = [];
  const bloqueos: BloqueoImpacto[] = [];

  const choques = agenda
    .filter(
      (t) =>
        t.fechaInicio.getTime() < fi &&
        t.fechaFin.getTime() > ini &&
        t.operarios.some((o) => enActividad.has(String(o.id))),
    )
    .sort((a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime() || a.id - b.id);

  for (const t of choques) {
    const tipo = String(t.tipo).toUpperCase();
    let motivo: MotivoBloqueoReemplazo | null = null;
    const confirmacion = tipoConfirmacionReemplazo(prioridad, t.prioridad ?? 2);
    if (tipo !== "PREVENTIVA") motivo = "NO_ES_PREVENTIVA";
    else if (!(ESTADOS_REEMPLAZABLES as readonly string[]).includes(String(t.estado))) motivo = "ESTADO";
    else if (!confirmacion) motivo = "PRIORIDAD";

    if (motivo) {
      bloqueos.push({ ...resumir(t), motivo, mensaje: mensajeBloqueo(motivo, t, prioridad) });
    } else {
      reemplazos.push({ ...resumir(t), tipoConfirmacion: confirmacion! });
    }
  }

  const reemplazarIds = reemplazos.map((r) => r.tareaId);
  const reemplazadas = new Set(reemplazarIds);

  // Operarios afectados: los de la actividad y quienes comparten una tarea
  // que se reemplaza (esa tarea se cancela completa también para ellos).
  const afectados: string[] = [...enActividad];
  for (const r of reemplazos) {
    for (const o of r.operarios) {
      if (!afectados.includes(o.id)) afectados.push(o.id);
    }
  }

  const operarios: OperarioImpacto[] = afectados.map((operarioId) => {
    const propias = agenda.filter((t) => t.operarios.some((o) => String(o.id) === operarioId));
    const suyasReemplazadas = propias.filter((t) => reemplazadas.has(t.id));
    const suyasBloqueos = bloqueos
      .filter((b) => b.operarios.some((o) => o.id === operarioId))
      .map((b) => b.tareaId);

    const base = suyasReemplazadas.map((t) => ({
      inicio: t.fechaInicio.getTime(),
      fin: t.fechaFin.getTime(),
    }));
    const cubierto: Tramo[] = propias
      .filter((t) => !reemplazadas.has(t.id))
      .map((t) => ({ inicio: t.fechaInicio.getTime(), fin: t.fechaFin.getTime() }));
    if (enActividad.has(operarioId)) cubierto.push({ inicio: ini, fin: fi });

    const huecos = restarTramos(base, cubierto)
      .map((h) => {
        const mins = minutos(h.fin - h.inicio);
        return {
          fechaInicio: new Date(h.inicio),
          fechaFin: new Date(h.fin),
          minutos: mins,
          grande: mins >= umbral,
        };
      })
      .filter((h) => h.minutos > 0);

    return {
      operarioId,
      nombre: nombres.get(operarioId) ?? operarioId,
      enLaActividad: enActividad.has(operarioId),
      reemplazadasIds: suyasReemplazadas.map((t) => t.id),
      bloqueosIds: suyasBloqueos,
      minutosReemplazados: unirTramos(base).reduce((s, t) => s + minutos(t.fin - t.inicio), 0),
      huecos,
      minutosHueco: huecos.reduce((s, h) => s + h.minutos, 0),
      huecoGrande: huecos.some((h) => h.grande),
    };
  });

  operarios.sort((a, b) => {
    if (a.enLaActividad !== b.enLaActividad) return a.enLaActividad ? -1 : 1;
    if (a.enLaActividad) {
      return afectados.indexOf(a.operarioId) - afectados.indexOf(b.operarioId);
    }
    return a.nombre.localeCompare(b.nombre, "es");
  });

  const prioridades = reemplazos.map((r) => r.prioridad);
  return {
    libre: choques.length === 0,
    puedeProgramar: bloqueos.length === 0,
    reemplazarIds,
    reemplazos,
    bloqueos,
    operarios,
    hayHuecoGrande: operarios.some((o) => o.huecoGrande),
    prioridadMasAltaReemplazada: prioridades.length ? Math.min(...prioridades) : null,
  };
}

/**
 * Primer horario del día (minutos desde las 00:00) donde la actividad cabe
 * completa sin reemplazar nada: dentro de [ventanas] y sin cruzarse con
 * [ocupados]. Busca desde [desdeMin] y, si no hay, desde el inicio del día.
 */
export function buscarHuecoLibreDia(params: {
  ventanas: Array<{ i: number; f: number }>;
  ocupados: Array<{ i: number; f: number }>;
  duracionMin: number;
  desdeMin: number;
}): number | null {
  const { duracionMin } = params;
  if (duracionMin <= 0) return null;
  const ocupados = unirTramos(params.ocupados.map((o) => ({ inicio: o.i, fin: o.f })));

  const candidatos = (desde: number): number | null => {
    for (const v of [...params.ventanas].sort((a, b) => a.i - b.i)) {
      let inicio = Math.max(v.i, desde);
      while (inicio + duracionMin <= v.f) {
        const fin = inicio + duracionMin;
        const choque = ocupados.find((o) => o.inicio < fin && o.fin > inicio);
        if (!choque) return inicio;
        inicio = choque.fin;
      }
    }
    return null;
  };

  return candidatos(params.desdeMin) ?? candidatos(0);
}
