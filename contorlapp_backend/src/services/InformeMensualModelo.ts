// Logica pura del informe mensual de actividades (sin base de datos ni PDF):
// agrupa las tareas del periodo, cruza con el cronograma para saber cuantas
// estaban previstas/programadas/realizadas y decide que fotos se muestran.

/** Estados en los que el operario ya cerro la tarea (cuenta como "hecha"). */
const ESTADOS_HECHA = new Set(["COMPLETADA", "APROBADA", "PENDIENTE_APROBACION"]);

/** Tope de tareas con foto que se muestran cuando una actividad es diaria. */
export const MAX_TAREAS_DIARIAS_CON_FOTO = 3;

const ORDEN_FRECUENCIAS = [
  "DIARIA",
  "SEMANAL",
  "QUINCENAL",
  "MENSUAL",
  "BIMESTRAL",
  "TRIMESTRAL",
  "SEMESTRAL",
  "ANUAL",
];

const ETIQUETA_FRECUENCIA: Record<string, string> = {
  DIARIA: "Diaria",
  SEMANAL: "Semanal",
  QUINCENAL: "Quincenal",
  MENSUAL: "Mensual",
  BIMESTRAL: "Bimestral",
  TRIMESTRAL: "Trimestral",
  SEMESTRAL: "Semestral",
  ANUAL: "Anual",
};

/* ------------------------------- entrada -------------------------------- */

export type TareaDetalleInforme = {
  id: number;
  tipo: string;
  frecuencia: string | null;
  descripcion: string;
  estado: string;
  fechaInicio: Date | string;
  fechaFin: Date | string;
  prioridad?: number | null;
  conjunto?: { id?: string | null; nombre?: string | null } | null;
  ubicacion?: { nombre?: string | null } | null;
  elemento?: { nombre?: string | null } | null;
  supervisor?: string | null;
  operarios?: string[] | null;
  evidencias?: string[] | null;
  insumos?: Array<Record<string, any>> | null;
  maquinaria?: Array<Record<string, any>> | null;
  herramientas?: Array<Record<string, any>> | null;
  observaciones?: string | null;
  reemplazaPreventivas?: Array<{
    tareaId: number;
    descripcion?: string | null;
    estadoActual?: string | null;
  }> | null;
};

export type ReemplazoInforme = {
  tareaPreventivaId: number;
  descripcion: string;
  reemplazadaEn?: Date | string | null;
  motivoUsuario?: string | null;
  resultado?: string | null;
  estadoActual?: string | null;
  reemplazadaPor?: {
    tareaId: number;
    descripcion?: string | null;
  } | null;
};

export type CronogramaInformeMes = {
  conjuntoId: string;
  ubicaciones: Array<{
    nombre: string;
    definiciones: Array<{
      id: string;
      descripcion: string;
      frecuencia: string | null;
      elementoNombre: string | null;
      ocurrencias: Array<{
        fechaObjetivo: Date | string;
        minutosProgramados: number;
        bloques: Array<{ tareaId: number; estado: string }>;
      }>;
    }>;
  }>;
};

export type EntradaInforme = {
  conjuntoNombre: string;
  desde: Date;
  hasta: Date;
  tareas: TareaDetalleInforme[];
  reemplazos: ReemplazoInforme[];
  cronogramas: CronogramaInformeMes[];
};

/* ------------------------------- salida --------------------------------- */

export type FotoInforme = { raw: string; tareaId: number; fecha: Date };

export type ReemplazoActividad = {
  tareaId: number;
  descripcion: string;
  motivo: string;
  porTareaId: number | null;
  porDescripcion: string | null;
};

export type ActividadInforme = {
  clave: string;
  tipo: "PREVENTIVA" | "CORRECTIVA";
  titulo: string;
  frecuencia: string | null;
  frecuenciaEtiqueta: string | null;
  esDiaria: boolean;
  conjunto: string | null;
  ubicacion: string | null;
  elemento: string | null;
  /** null cuando no hay cronograma que respalde la cifra. */
  previstas: number | null;
  programadas: number | null;
  realizadas: number;
  /** Base sobre la que se mide "realizadas": programadas o, sin cronograma, registros. */
  baseRealizadas: number;
  registros: number;
  noCompletadas: number;
  ids: number[];
  inicio: Date | null;
  fin: Date | null;
  supervisores: string[];
  operarios: string[];
  recursos: { insumos: string; maquinaria: string; herramientas: string };
  fotos: FotoInforme[];
  fotosTotales: number;
  /** Fotos que existen pero no se imprimen (solo en tareas diarias). */
  fotosOmitidas: number;
  tareasConFoto: number;
  observaciones: string[];
  /** Solo correctivas: a que preventivas reemplazaron. */
  reemplazaA: ReemplazoActividad[];
  /** Solo preventivas: reemplazos ocurridos dentro de esta actividad. */
  reemplazadas: ReemplazoActividad[];
};

export type TareaReemplazadaInforme = {
  tareaId: number;
  descripcion: string;
  fecha: Date | null;
  motivo: string;
  estadoActual: string | null;
  porTareaId: number | null;
  porDescripcion: string | null;
};

export type InformeMensual = {
  conjuntoNombre: string;
  desde: Date;
  hasta: Date;
  resumen: {
    previstas: number;
    programadas: number;
    realizadas: number;
    hayCronograma: boolean;
    totalTareas: number;
    preventivas: number;
    correctivas: number;
    reemplazadas: number;
    noCompletadas: number;
    porEstado: Array<{ estado: string; cantidad: number }>;
  };
  preventivas: ActividadInforme[];
  correctivas: ActividadInforme[];
  reemplazadas: TareaReemplazadaInforme[];
};

/* ------------------------------ utilidades ------------------------------ */

function sinTildes(v: string) {
  return v.normalize("NFD").replace(/\p{M}/gu, "");
}

export function normalizarFrecuencia(raw: string | null | undefined): string {
  return sinTildes(String(raw ?? ""))
    .trim()
    .toUpperCase()
    .replace(/[\s-]+/g, "_");
}

function claveFrecuenciaBase(raw: string | null | undefined): string {
  const key = normalizarFrecuencia(raw);
  if (key === "DIARIO") return "DIARIA";
  const base = ORDEN_FRECUENCIAS.find(
    (f) => key === f || key.startsWith(`${f}_`),
  );
  return base ?? key;
}

export function esFrecuenciaDiaria(raw: string | null | undefined): boolean {
  return claveFrecuenciaBase(raw) === "DIARIA";
}

export function etiquetaFrecuencia(raw: string | null | undefined): string | null {
  const key = normalizarFrecuencia(raw);
  if (!key) return null;
  const base = claveFrecuenciaBase(raw);
  if (ETIQUETA_FRECUENCIA[base]) return ETIQUETA_FRECUENCIA[base];
  const legible = key.replace(/_/g, " ").toLowerCase();
  return legible.charAt(0).toUpperCase() + legible.slice(1);
}

function ordenFrecuencia(raw: string | null | undefined): number {
  const idx = ORDEN_FRECUENCIAS.indexOf(claveFrecuenciaBase(raw));
  return idx < 0 ? ORDEN_FRECUENCIAS.length : idx;
}

const TZ = "America/Bogota";
const fmtDia = new Intl.DateTimeFormat("en-CA", {
  timeZone: TZ,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** YYYY-MM-DD en hora de Colombia (evita que un UTC-5 corra el dia). */
export function claveDia(value: Date | string): string {
  return fmtDia.format(new Date(value));
}

function aFecha(value: Date | string): Date {
  return value instanceof Date ? value : new Date(value);
}

function unicos(items: Array<string | null | undefined>): string[] {
  const out: string[] = [];
  const vistos = new Set<string>();
  for (const item of items) {
    const v = String(item ?? "").trim();
    if (!v) continue;
    // Sin tildes ni signos: "no se realizó." y "No se realizo" son la misma nota.
    const k = normalizarClave(v) || v.toUpperCase();
    if (vistos.has(k)) continue;
    vistos.add(k);
    out.push(v);
  }
  return out;
}

function normalizarClave(v: string | null | undefined): string {
  return sinTildes(String(v ?? ""))
    .toUpperCase()
    .replace(/\s+/g, " ")
    .replace(/[^A-Z0-9 ]/g, "")
    .trim();
}

function esHecha(estado: string) {
  return ESTADOS_HECHA.has(String(estado ?? "").toUpperCase());
}

/** Elige `max` posiciones repartidas de forma pareja entre 0..total-1. */
export function posicionesRepartidas(total: number, max: number): number[] {
  if (total <= 0 || max <= 0) return [];
  if (total <= max) return Array.from({ length: total }, (_, i) => i);
  if (max === 1) return [0];
  const out = new Set<number>();
  for (let k = 0; k < max; k++) {
    out.add(Math.round((k * (total - 1)) / (max - 1)));
  }
  return Array.from(out).sort((a, b) => a - b);
}

function cantidadTexto(v: unknown): string {
  const n = Number(v);
  if (!Number.isFinite(n) || n <= 0) return "";
  return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/\.?0+$/, "");
}

function resumirRecursos(
  tareas: TareaDetalleInforme[],
  campo: "insumos" | "maquinaria" | "herramientas",
  max = 5,
): string {
  const acumulado = new Map<
    string,
    { nombre: string; unidad: string; cantidad: number }
  >();
  for (const t of tareas) {
    for (const r of t[campo] ?? []) {
      const nombre = String(r?.nombre ?? "").trim();
      if (!nombre) continue;
      const unidad = String(r?.unidad ?? "").trim();
      const key = `${nombre.toUpperCase()}|${unidad.toUpperCase()}`;
      const slot = acumulado.get(key) ?? { nombre, unidad, cantidad: 0 };
      const n = Number(r?.cantidad);
      if (Number.isFinite(n)) slot.cantidad += n;
      acumulado.set(key, slot);
    }
  }
  const lista = Array.from(acumulado.values());
  if (lista.length === 0) return "";
  const texto = lista.slice(0, max).map((r) => {
    const qty = [cantidadTexto(r.cantidad), r.unidad].filter(Boolean).join(" ");
    return qty ? `${r.nombre} (${qty})` : r.nombre;
  });
  if (lista.length > max) texto.push(`y ${lista.length - max} más`);
  return texto.join(", ");
}

function motivoLegible(r: ReemplazoInforme): string {
  const usuario = String(r.motivoUsuario ?? "").trim();
  const resultado = String(r.resultado ?? "").trim().toUpperCase();
  const porResultado =
    resultado === "REPROGRAMADA"
      ? "Se reprogramó para otra fecha."
      : resultado === "CANCELADA_AUTO"
        ? "Se canceló para dar prioridad a la correctiva."
        : resultado === "CANCELADA_SIN_CUPO"
          ? "Se canceló por falta de cupo en la agenda."
          : "Se reemplazó por una tarea correctiva.";
  return usuario ? `${usuario}` : porResultado;
}

/* ------------------------------ construccion ---------------------------- */

type GrupoPreventiva = {
  clave: string;
  conjuntoId: string | null;
  ubicacion: string | null;
  elemento: string | null;
  titulo: string;
  frecuencia: string | null;
  previstas: number | null;
  programadas: number | null;
  realizadasCronograma: number | null;
  tareas: TareaDetalleInforme[];
};

export function construirInformeMensual(entrada: EntradaInforme): InformeMensual {
  const { desde, hasta } = entrada;
  const dDesde = claveDia(desde);
  const dHasta = claveDia(hasta);
  const enRango = (f: Date | string) => {
    const k = claveDia(f);
    return k >= dDesde && k <= dHasta;
  };

  const grupos = new Map<string, GrupoPreventiva>();
  const grupoPorTarea = new Map<number, string>();

  // 1) Cronograma: define las actividades y sus cifras previstas/programadas.
  let hayCronograma = false;
  for (const cron of entrada.cronogramas) {
    for (const ubic of cron.ubicaciones) {
      for (const def of ubic.definiciones) {
        const ocurrencias = def.ocurrencias.filter((o) => enRango(o.fechaObjetivo));
        if (ocurrencias.length === 0) continue;
        hayCronograma = true;
        const clave = `cron:${cron.conjuntoId}:${def.id}`;
        const grupo: GrupoPreventiva = grupos.get(clave) ?? {
          clave,
          conjuntoId: cron.conjuntoId,
          ubicacion: ubic.nombre,
          elemento: def.elementoNombre,
          titulo: def.descripcion,
          frecuencia: def.frecuencia,
          previstas: 0,
          programadas: 0,
          realizadasCronograma: 0,
          tareas: [],
        };
        for (const oc of ocurrencias) {
          grupo.previstas! += 1;
          if (oc.minutosProgramados > 0) grupo.programadas! += 1;
          if (oc.bloques.length > 0 && oc.bloques.every((b) => esHecha(b.estado))) {
            grupo.realizadasCronograma! += 1;
          }
          for (const b of oc.bloques) grupoPorTarea.set(b.tareaId, clave);
        }
        grupos.set(clave, grupo);
      }
    }
  }

  // 2) Tareas del periodo: preventivas a su actividad, el resto a correctivas.
  const ordenadas = [...entrada.tareas].sort(
    (a, b) => aFecha(a.fechaInicio).getTime() - aFecha(b.fechaInicio).getTime(),
  );
  const correctivasRaw: TareaDetalleInforme[] = [];
  for (const t of ordenadas) {
    if (String(t.tipo).toUpperCase() !== "PREVENTIVA") {
      correctivasRaw.push(t);
      continue;
    }
    let clave = grupoPorTarea.get(t.id);
    if (!clave) {
      clave = [
        "libre",
        t.conjunto?.id ?? "",
        claveFrecuenciaBase(t.frecuencia),
        normalizarClave(t.descripcion),
        normalizarClave(t.ubicacion?.nombre),
        normalizarClave(t.elemento?.nombre),
      ].join("|");
    }
    let grupo = grupos.get(clave);
    if (!grupo) {
      grupo = {
        clave,
        conjuntoId: t.conjunto?.id ?? null,
        ubicacion: t.ubicacion?.nombre ?? null,
        elemento: t.elemento?.nombre ?? null,
        titulo: t.descripcion,
        frecuencia: t.frecuencia,
        previstas: null,
        programadas: null,
        realizadasCronograma: null,
        tareas: [],
      };
      grupos.set(clave, grupo);
    }
    grupo.tareas.push(t);
  }

  // 3) Reemplazos indexados por la preventiva y por la correctiva.
  const reemplazoPorPreventiva = new Map<number, ReemplazoInforme>();
  const reemplazosPorCorrectiva = new Map<number, ReemplazoInforme[]>();
  for (const r of entrada.reemplazos) {
    if (!reemplazoPorPreventiva.has(r.tareaPreventivaId)) {
      reemplazoPorPreventiva.set(r.tareaPreventivaId, r);
    }
    const correctivaId = r.reemplazadaPor?.tareaId;
    if (typeof correctivaId === "number") {
      const lista = reemplazosPorCorrectiva.get(correctivaId) ?? [];
      lista.push(r);
      reemplazosPorCorrectiva.set(correctivaId, lista);
    }
  }

  const toReemplazoActividad = (r: ReemplazoInforme): ReemplazoActividad => ({
    tareaId: r.tareaPreventivaId,
    descripcion: r.descripcion,
    motivo: motivoLegible(r),
    porTareaId: r.reemplazadaPor?.tareaId ?? null,
    porDescripcion: r.reemplazadaPor?.descripcion ?? null,
  });

  const construirActividad = (
    tipo: "PREVENTIVA" | "CORRECTIVA",
    base: {
      clave: string;
      titulo: string;
      frecuencia: string | null;
      conjunto: string | null;
      ubicacion: string | null;
      elemento: string | null;
      previstas: number | null;
      programadas: number | null;
      realizadasCronograma: number | null;
    },
    tareas: TareaDetalleInforme[],
  ): ActividadInforme => {
    const diaria = tipo === "PREVENTIVA" && esFrecuenciaDiaria(base.frecuencia);

    const conFoto = tareas
      .map((t) => ({
        t,
        raws: unicos(t.evidencias ?? []),
      }))
      .filter((x) => x.raws.length > 0);
    const fotosTotales = conFoto.reduce((acc, x) => acc + x.raws.length, 0);

    let seleccion = conFoto;
    let fotos: FotoInforme[];
    if (diaria && conFoto.length > MAX_TAREAS_DIARIAS_CON_FOTO) {
      seleccion = posicionesRepartidas(
        conFoto.length,
        MAX_TAREAS_DIARIAS_CON_FOTO,
      ).map((i) => conFoto[i]);
      fotos = seleccion.map((x) => ({
        raw: x.raws[0],
        tareaId: x.t.id,
        fecha: aFecha(x.t.fechaFin),
      }));
    } else {
      fotos = seleccion.flatMap((x) =>
        x.raws.map((raw) => ({
          raw,
          tareaId: x.t.id,
          fecha: aFecha(x.t.fechaFin),
        })),
      );
    }

    const hechasLocal = tareas.filter((t) => esHecha(t.estado)).length;
    const hayCifras = base.previstas != null;
    const realizadas = hayCifras
      ? (base.realizadasCronograma ?? 0)
      : hechasLocal;
    const baseRealizadas = hayCifras ? (base.programadas ?? 0) : tareas.length;

    const fechas = tareas.map((t) => aFecha(t.fechaInicio).getTime());
    const fechasFin = tareas.map((t) => aFecha(t.fechaFin).getTime());

    const reemplazadas =
      tipo === "PREVENTIVA"
        ? tareas
            .map((t) => reemplazoPorPreventiva.get(t.id))
            .filter((r): r is ReemplazoInforme => r != null)
            .map(toReemplazoActividad)
        : [];
    const reemplazaA =
      tipo === "CORRECTIVA"
        ? tareas.flatMap((t) => {
            const filas = reemplazosPorCorrectiva.get(t.id) ?? [];
            if (filas.length > 0) return filas.map(toReemplazoActividad);
            return (t.reemplazaPreventivas ?? []).map((p) => ({
              tareaId: p.tareaId,
              descripcion: String(p.descripcion ?? "").trim(),
              motivo: "Se reemplazó por una tarea correctiva.",
              porTareaId: t.id,
              porDescripcion: t.descripcion,
            }));
          })
        : [];

    return {
      clave: base.clave,
      tipo,
      titulo: base.titulo,
      frecuencia: base.frecuencia,
      frecuenciaEtiqueta: etiquetaFrecuencia(base.frecuencia),
      esDiaria: diaria,
      conjunto: base.conjunto,
      ubicacion: base.ubicacion,
      elemento: base.elemento,
      previstas: base.previstas,
      programadas: base.programadas,
      realizadas,
      baseRealizadas,
      registros: tareas.length,
      noCompletadas: tareas.filter(
        (t) => String(t.estado).toUpperCase() === "NO_COMPLETADA",
      ).length,
      ids: tareas.map((t) => t.id),
      inicio: fechas.length ? new Date(Math.min(...fechas)) : null,
      fin: fechasFin.length ? new Date(Math.max(...fechasFin)) : null,
      supervisores: unicos(tareas.map((t) => t.supervisor)),
      operarios: unicos(tareas.flatMap((t) => t.operarios ?? [])),
      recursos: {
        insumos: resumirRecursos(tareas, "insumos"),
        maquinaria: resumirRecursos(tareas, "maquinaria"),
        herramientas: resumirRecursos(tareas, "herramientas"),
      },
      fotos,
      fotosTotales,
      fotosOmitidas: Math.max(0, fotosTotales - fotos.length),
      tareasConFoto: conFoto.length,
      observaciones: unicos(tareas.map((t) => t.observaciones)).slice(0, 2),
      reemplazaA,
      reemplazadas,
    };
  };

  // 4) Actividades preventivas (incluye las previstas que nunca se programaron).
  const preventivas = Array.from(grupos.values())
    .map((g) =>
      construirActividad(
        "PREVENTIVA",
        {
          clave: g.clave,
          titulo: g.titulo,
          frecuencia: g.frecuencia,
          conjunto: null,
          ubicacion: g.ubicacion,
          elemento: g.elemento,
          previstas: g.previstas,
          programadas: g.programadas,
          realizadasCronograma: g.realizadasCronograma,
        },
        g.tareas,
      ),
    )
    .sort(
      (a, b) =>
        ordenFrecuencia(a.frecuencia) - ordenFrecuencia(b.frecuencia) ||
        String(a.ubicacion ?? "").localeCompare(String(b.ubicacion ?? ""), "es") ||
        a.titulo.localeCompare(b.titulo, "es"),
    );

  const correctivas = correctivasRaw.map((t) =>
    construirActividad(
      "CORRECTIVA",
      {
        clave: `correctiva:${t.id}`,
        titulo: t.descripcion,
        frecuencia: null,
        conjunto: t.conjunto?.nombre ?? null,
        ubicacion: t.ubicacion?.nombre ?? null,
        elemento: t.elemento?.nombre ?? null,
        previstas: null,
        programadas: null,
        realizadasCronograma: null,
      },
      [t],
    ),
  );

  const reemplazadas: TareaReemplazadaInforme[] = [];
  const vistas = new Set<number>();
  for (const r of entrada.reemplazos) {
    if (vistas.has(r.tareaPreventivaId)) continue;
    vistas.add(r.tareaPreventivaId);
    reemplazadas.push({
      tareaId: r.tareaPreventivaId,
      descripcion: r.descripcion,
      fecha: r.reemplazadaEn ? aFecha(r.reemplazadaEn) : null,
      motivo: motivoLegible(r),
      estadoActual: r.estadoActual ?? null,
      porTareaId: r.reemplazadaPor?.tareaId ?? null,
      porDescripcion: r.reemplazadaPor?.descripcion ?? null,
    });
  }

  // 5) Resumen general.
  const conteoEstados = new Map<string, number>();
  for (const t of entrada.tareas) {
    const e = String(t.estado ?? "").toUpperCase();
    conteoEstados.set(e, (conteoEstados.get(e) ?? 0) + 1);
  }
  const conCifras = preventivas.filter((a) => a.previstas != null);

  return {
    conjuntoNombre: entrada.conjuntoNombre,
    desde,
    hasta,
    resumen: {
      previstas: conCifras.reduce((acc, a) => acc + (a.previstas ?? 0), 0),
      programadas: conCifras.reduce((acc, a) => acc + (a.programadas ?? 0), 0),
      realizadas: conCifras.reduce((acc, a) => acc + a.realizadas, 0),
      hayCronograma,
      totalTareas: entrada.tareas.length,
      preventivas: entrada.tareas.filter(
        (t) => String(t.tipo).toUpperCase() === "PREVENTIVA",
      ).length,
      correctivas: correctivasRaw.length,
      reemplazadas: reemplazadas.length,
      noCompletadas: conteoEstados.get("NO_COMPLETADA") ?? 0,
      porEstado: Array.from(conteoEstados.entries())
        .map(([estado, cantidad]) => ({ estado, cantidad }))
        .sort((a, b) => b.cantidad - a.cantidad),
    },
    preventivas,
    correctivas,
    reemplazadas,
  };
}
