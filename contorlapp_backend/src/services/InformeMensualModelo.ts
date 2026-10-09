// Logica pura del informe mensual de actividades (sin base de datos ni PDF):
// agrupa las tareas del periodo, cruza con el cronograma para saber cuantas
// estaban previstas/programadas/realizadas y decide que fotos se muestran.
import {
  MAX_FOTOS_POR_TAREA,
  hayFiltros,
  limiteFotosInforme,
  opcionesPorDefecto,
  type OpcionesInforme,
} from "./InformeMensualOpciones";

/** Estados en los que el operario ya cerro la tarea (cuenta como "hecha"). */
const ESTADOS_HECHA = new Set(["COMPLETADA", "APROBADA", "PENDIENTE_APROBACION"]);

/** Estados que van a "Novedades y pendientes" sin importar la fecha. */
const ESTADOS_NOVEDAD = new Set([
  "NO_COMPLETADA",
  "PENDIENTE_REPROGRAMACION",
  "RECHAZADA",
]);

/** Estados abiertos: si su fecha ya paso, la tarea esta vencida sin cerrar. */
const ESTADOS_ABIERTOS = new Set(["ASIGNADA", "EN_PROCESO"]);

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
  /** Cuando el operario empezo y cerro la tarea (puntualidad y duracion real). */
  fechaIniciarTarea?: Date | string | null;
  fechaFinalizarTarea?: Date | string | null;
  duracionMinutos?: number | null;
  /** Interno: por que el supervisor devolvio el cierre. */
  observacionesRechazo?: string | null;
  motivoNoCompletada?: string | null;
  /** Interno: nombre de quien cerro la tarea (lo resuelve el servicio). */
  cerradoPor?: string | null;
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
  /** Referencia para saber si una tarea abierta ya esta vencida. */
  ahora?: Date;
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

/** Cuando y como se cerro una tarea frente a lo programado. */
export type PuntualidadTarea = {
  programadaInicio: Date;
  programadaFin: Date;
  inicioReal: Date | null;
  cierreReal: Date | null;
  /** 0 = cerrada el mismo dia programado (o antes); null = sin cierre registrado. */
  diasRetraso: number | null;
  duracionRealMin: number | null;
  duracionProgramadaMin: number | null;
};

/** Datos de una sola tarea, cuando el bloque del PDF es una tarea (no una actividad agrupada). */
export type DetalleTareaInforme = {
  id: number;
  estado: string;
  puntualidad: PuntualidadTarea;
  motivoNoCompletada: string | null;
};

export type ActividadInforme = {
  clave: string;
  tipo: "PREVENTIVA" | "CORRECTIVA";
  titulo: string;
  frecuencia: string | null;
  frecuenciaEtiqueta: string | null;
  esDiaria: boolean;
  conjuntoId: string | null;
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
  /** Cuantas tareas hay en cada estado. */
  estados: Array<{ estado: string; cantidad: number }>;
  /** Tareas con cierre registrado y cuantas se cerraron el dia programado. */
  puntualidad: { cerradas: number; aTiempo: number; conRetraso: number };
  /** Internos (vacios si el rol no puede verlos). */
  cerradoPor: string[];
  motivosRechazo: string[];
  /** Solo cuando el bloque representa una sola tarea. */
  tarea: DetalleTareaInforme | null;
};

/**
 * Bloques del cuerpo del informe segun la organizacion elegida:
 * por actividad (preventivas y correctivas), por ubicacion o por dia.
 */
export type SeccionInforme =
  | { tipo: "PREVENTIVAS"; actividades: ActividadInforme[] }
  | { tipo: "CORRECTIVAS"; actividades: ActividadInforme[] }
  | { tipo: "UBICACION"; titulo: string; actividades: ActividadInforme[] }
  | { tipo: "DIA"; fecha: Date; actividades: ActividadInforme[] };

export type FilaCumplimiento = {
  titulo: string;
  frecuencia: string | null;
  ubicacion: string | null;
  previstas: number | null;
  programadas: number | null;
  realizadas: number;
  base: number;
  /** 0-100, o null si no hay base para medirlo. */
  porcentaje: number | null;
};

export type FilaNovedad = {
  tareaId: number;
  fecha: Date;
  tipo: string;
  descripcion: string;
  ubicacion: string | null;
  estado: string;
  /** VENCIDA cuando la tarea sigue abierta y su fecha ya paso. */
  novedad: string;
  motivo: string;
};

export type FilaRecurso = {
  nombre: string;
  unidad: string;
  cantidad: number;
  tareas: number;
};

export type FilaAnexo = {
  tareaId: number;
  tipo: string;
  fecha: Date;
  cierre: Date | null;
  ubicacion: string | null;
  descripcion: string;
  estado: string;
  responsables: string;
  evidencias: number;
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
  opciones: OpcionesInforme;
  /** True si hay filtros: el informe no incluye todas las tareas del periodo. */
  filtrado: boolean;
  /** Cuerpo del informe segun la organizacion (vacio si no se pidio el detalle). */
  secciones: SeccionInforme[];
  cumplimiento: FilaCumplimiento[];
  novedades: FilaNovedad[];
  consolidado: {
    insumos: FilaRecurso[];
    maquinaria: FilaRecurso[];
    herramientas: FilaRecurso[];
  };
  anexo: FilaAnexo[];
  fotos: { incluidas: number; omitidasPorLimite: number; limite: number };
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

/* ------------------------- opciones y puntualidad ----------------------- */

function fechaOpcional(value: Date | string | null | undefined): Date | null {
  if (value == null || value === "") return null;
  const d = aFecha(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function tipoDe(t: TareaDetalleInforme): "PREVENTIVA" | "CORRECTIVA" {
  return String(t.tipo).toUpperCase() === "PREVENTIVA" ? "PREVENTIVA" : "CORRECTIVA";
}

function texto(v: string | null | undefined): string {
  return String(v ?? "").trim();
}

const DIA_MS = 86_400_000;

function diasEntre(desdeClave: string, hastaClave: string): number {
  return Math.round(
    (Date.parse(`${hastaClave}T00:00:00Z`) - Date.parse(`${desdeClave}T00:00:00Z`)) /
      DIA_MS,
  );
}

/** Programada vs. real: "a tiempo" es cerrar el mismo dia programado o antes. */
export function puntualidadDeTarea(t: TareaDetalleInforme): PuntualidadTarea {
  const programadaFin = aFecha(t.fechaFin);
  const inicioReal = fechaOpcional(t.fechaIniciarTarea);
  const cierreReal = fechaOpcional(t.fechaFinalizarTarea);
  const finValido = !Number.isNaN(programadaFin.getTime());
  const diasRetraso =
    cierreReal && finValido
      ? Math.max(0, diasEntre(claveDia(programadaFin), claveDia(cierreReal)))
      : null;
  const duracionRealMin =
    inicioReal && cierreReal && cierreReal.getTime() >= inicioReal.getTime()
      ? Math.round((cierreReal.getTime() - inicioReal.getTime()) / 60_000)
      : null;
  const programada = Number(t.duracionMinutos);
  return {
    programadaInicio: aFecha(t.fechaInicio),
    programadaFin,
    inicioReal,
    cierreReal,
    diasRetraso,
    duracionRealMin,
    duracionProgramadaMin: Number.isFinite(programada) && programada > 0 ? programada : null,
  };
}

function crearFiltroTareas(opciones: OpcionesInforme) {
  const f = opciones.filtros;
  const tipos = f.tipos ? new Set<string>(f.tipos) : null;
  const estados = f.estados ? new Set<string>(f.estados) : null;
  const frecuencias = f.frecuencias
    ? new Set(f.frecuencias.map((x) => claveFrecuenciaBase(x)))
    : null;
  const ubicaciones = f.ubicaciones
    ? new Set(f.ubicaciones.map((x) => normalizarClave(x)))
    : null;
  return (t: TareaDetalleInforme): boolean => {
    const tipo = tipoDe(t);
    if (tipos && !tipos.has(tipo)) return false;
    if (estados && !estados.has(String(t.estado ?? "").toUpperCase())) return false;
    // La frecuencia solo existe en preventivas: las correctivas se filtran por tipo.
    if (
      frecuencias &&
      tipo === "PREVENTIVA" &&
      !frecuencias.has(claveFrecuenciaBase(t.frecuencia))
    ) {
      return false;
    }
    if (ubicaciones && !ubicaciones.has(normalizarClave(t.ubicacion?.nombre))) {
      return false;
    }
    if (f.soloConEvidencia && unicos(t.evidencias ?? []).length === 0) return false;
    return true;
  };
}

/**
 * Fotos que se imprimen de un grupo de tareas. AUTO conserva la regla de
 * siempre: en diarias con muchos registros, 3 repartidos con 1 foto cada uno;
 * en lo demas, todas.
 */
function seleccionarFotos(
  diaria: boolean,
  tareas: TareaDetalleInforme[],
  o: OpcionesInforme["fotos"],
): { fotos: FotoInforme[]; fotosTotales: number; tareasConFoto: number } {
  const conFoto = tareas
    .map((t) => ({ t, raws: unicos(t.evidencias ?? []) }))
    .filter((x) => x.raws.length > 0);
  const fotosTotales = conFoto.reduce((acc, x) => acc + x.raws.length, 0);
  if (!o.incluir) return { fotos: [], fotosTotales, tareasConFoto: conFoto.length };

  let seleccion = conFoto;
  let porRegistro = o.porTarea ?? MAX_FOTOS_POR_TAREA;
  const modo = o.registrosPorActividad;
  if (modo === "AUTO") {
    if (diaria && conFoto.length > MAX_TAREAS_DIARIAS_CON_FOTO) {
      seleccion = posicionesRepartidas(conFoto.length, MAX_TAREAS_DIARIAS_CON_FOTO).map(
        (i) => conFoto[i],
      );
      porRegistro = o.porTarea ?? 1;
    }
  } else if (modo !== "TODOS") {
    seleccion = posicionesRepartidas(conFoto.length, modo).map((i) => conFoto[i]);
  }

  const fotos = seleccion.flatMap((x) => {
    const fecha = fechaOpcional(x.t.fechaFinalizarTarea) ?? aFecha(x.t.fechaFin);
    return posicionesRepartidas(x.raws.length, porRegistro).map((i) => ({
      raw: x.raws[i],
      tareaId: x.t.id,
      fecha,
    }));
  });
  return { fotos, fotosTotales, tareasConFoto: conFoto.length };
}

/**
 * Si el informe pide mas fotos que el tope, recorta cada actividad en
 * proporcion (al menos 1 por actividad mientras alcance) y de forma pareja.
 * Devuelve cuantas fotos se omitieron.
 */
function aplicarTopeFotos(actividades: ActividadInforme[], limite: number): number {
  const conFotos = actividades.filter((a) => a.fotos.length > 0);
  const total = conFotos.reduce((acc, a) => acc + a.fotos.length, 0);
  if (total <= limite) return 0;

  const cuotas = new Map<ActividadInforme, number>();
  for (const a of conFotos) {
    cuotas.set(a, Math.max(1, Math.floor((a.fotos.length * limite) / total)));
  }
  let suma = Array.from(cuotas.values()).reduce((acc, c) => acc + c, 0);
  const orden = [...conFotos].sort((a, b) => cuotas.get(b)! - cuotas.get(a)!);
  while (suma > limite) {
    let redujo = false;
    for (const a of orden) {
      if (suma <= limite) break;
      const c = cuotas.get(a)!;
      if (c > 0) {
        cuotas.set(a, c - 1);
        suma -= 1;
        redujo = true;
      }
    }
    if (!redujo) break;
  }

  let quedan = 0;
  for (const a of conFotos) {
    const c = cuotas.get(a)!;
    if (c < a.fotos.length) {
      a.fotos = posicionesRepartidas(a.fotos.length, c).map((i) => a.fotos[i]);
      a.fotosOmitidas = Math.max(0, a.fotosTotales - a.fotos.length);
    }
    quedan += a.fotos.length;
  }
  return total - quedan;
}

function contarEstados(tareas: TareaDetalleInforme[]) {
  const conteo = new Map<string, number>();
  for (const t of tareas) {
    const e = String(t.estado ?? "").toUpperCase();
    conteo.set(e, (conteo.get(e) ?? 0) + 1);
  }
  return Array.from(conteo.entries())
    .map(([estado, cantidad]) => ({ estado, cantidad }))
    .sort((a, b) => b.cantidad - a.cantidad);
}

function consolidarRecursos(
  tareas: TareaDetalleInforme[],
  campo: "insumos" | "maquinaria" | "herramientas",
): FilaRecurso[] {
  // La maquinaria no tiene cantidad: se cuentan sus usos.
  const contarUsos = campo === "maquinaria";
  const acumulado = new Map<
    string,
    { nombre: string; unidad: string; cantidad: number; tareas: Set<number> }
  >();
  for (const t of tareas) {
    for (const r of t[campo] ?? []) {
      const nombre = texto(r?.nombre);
      if (!nombre) continue;
      const unidad = contarUsos ? "" : texto(r?.unidad);
      const key = `${normalizarClave(nombre)}|${unidad.toUpperCase()}`;
      const slot =
        acumulado.get(key) ?? { nombre, unidad, cantidad: 0, tareas: new Set<number>() };
      if (contarUsos) {
        slot.cantidad += 1;
      } else {
        const n = Number(r?.cantidad);
        if (Number.isFinite(n)) slot.cantidad += n;
      }
      slot.tareas.add(t.id);
      acumulado.set(key, slot);
    }
  }
  return Array.from(acumulado.values())
    .map((r) => ({
      nombre: r.nombre,
      unidad: r.unidad,
      cantidad: Math.round(r.cantidad * 100) / 100,
      tareas: r.tareas.size,
    }))
    .sort((a, b) => a.nombre.localeCompare(b.nombre, "es"));
}

function motivoNovedad(
  t: TareaDetalleInforme,
  estado: string,
  verMotivoRechazo: boolean,
): string {
  const noCompletada = texto(t.motivoNoCompletada);
  if (noCompletada) return noCompletada;
  if (estado === "RECHAZADA") {
    const rechazo = texto(t.observacionesRechazo);
    return verMotivoRechazo && rechazo ? rechazo : "Devuelta para corrección.";
  }
  if (ESTADOS_ABIERTOS.has(estado)) {
    return "Su fecha programada ya pasó y sigue sin cierre.";
  }
  const obs = texto(t.observaciones);
  if (obs) return obs;
  if (estado === "PENDIENTE_REPROGRAMACION") return "Pendiente de una nueva fecha.";
  return "Sin motivo registrado.";
}

/** Todas las actividades que se dibujan en el cuerpo (y cuyas fotos se cargan). */
export function actividadesDelCuerpo(informe: InformeMensual): ActividadInforme[] {
  const vistas = new Set<ActividadInforme>();
  for (const s of informe.secciones) {
    for (const a of s.actividades) vistas.add(a);
  }
  return Array.from(vistas);
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

type BaseActividad = {
  clave: string;
  titulo: string;
  frecuencia: string | null;
  conjuntoId: string | null;
  conjunto: string | null;
  ubicacion: string | null;
  elemento: string | null;
  previstas: number | null;
  programadas: number | null;
  realizadasCronograma: number | null;
};

export function construirInformeMensual(
  entrada: EntradaInforme,
  opcionesEntrada?: OpcionesInforme,
): InformeMensual {
  const opciones = opcionesEntrada ?? opcionesPorDefecto();
  const filtrado = hayFiltros(opciones);
  const { desde, hasta } = entrada;
  const dDesde = claveDia(desde);
  const dHasta = claveDia(hasta);
  const enRango = (f: Date | string) => {
    const k = claveDia(f);
    return k >= dDesde && k <= dHasta;
  };

  const cumpleFiltros = crearFiltroTareas(opciones);
  const tareasFiltradas = entrada.tareas.filter(cumpleFiltros);
  const tiposIncluidos = new Set<string>(
    opciones.filtros.tipos ?? ["PREVENTIVA", "CORRECTIVA"],
  );

  const nombreConjunto = new Map<string, string>();
  for (const t of entrada.tareas) {
    const id = t.conjunto?.id;
    const nombre = texto(t.conjunto?.nombre);
    if (id && nombre && !nombreConjunto.has(id)) nombreConjunto.set(id, nombre);
  }

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
  const ordenadas = [...tareasFiltradas].sort(
    (a, b) => aFecha(a.fechaInicio).getTime() - aFecha(b.fechaInicio).getTime(),
  );
  const correctivasRaw: TareaDetalleInforme[] = [];
  for (const t of ordenadas) {
    if (tipoDe(t) !== "PREVENTIVA") {
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
    base: BaseActividad,
    tareas: TareaDetalleInforme[],
    esTarea: boolean,
  ): ActividadInforme => {
    const diaria = tipo === "PREVENTIVA" && esFrecuenciaDiaria(base.frecuencia);
    const { fotos, fotosTotales, tareasConFoto } = seleccionarFotos(
      diaria,
      tareas,
      opciones.fotos,
    );

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

    const puntualidades = tareas.map(puntualidadDeTarea);
    const cerradas = puntualidades.filter((p) => p.diasRetraso != null);
    const aTiempo = cerradas.filter((p) => p.diasRetraso === 0).length;

    return {
      clave: base.clave,
      tipo,
      titulo: base.titulo,
      frecuencia: base.frecuencia,
      frecuenciaEtiqueta: etiquetaFrecuencia(base.frecuencia),
      esDiaria: diaria,
      conjuntoId: base.conjuntoId,
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
      tareasConFoto,
      observaciones: unicos(tareas.map((t) => t.observaciones)).slice(0, 2),
      reemplazaA,
      reemplazadas,
      estados: contarEstados(tareas),
      puntualidad: {
        cerradas: cerradas.length,
        aTiempo,
        conRetraso: cerradas.length - aTiempo,
      },
      cerradoPor: opciones.campos.cerradoPor
        ? unicos(tareas.map((t) => t.cerradoPor))
        : [],
      motivosRechazo: opciones.campos.motivoRechazo
        ? unicos(tareas.map((t) => t.observacionesRechazo)).slice(0, 3)
        : [],
      tarea:
        esTarea && tareas.length === 1
          ? {
              id: tareas[0].id,
              estado: String(tareas[0].estado ?? "").toUpperCase(),
              puntualidad: puntualidades[0],
              motivoNoCompletada: texto(tareas[0].motivoNoCompletada) || null,
            }
          : null,
    };
  };

  const baseDeTarea = (t: TareaDetalleInforme): BaseActividad => ({
    clave: `tarea:${t.id}`,
    titulo: t.descripcion,
    frecuencia: tipoDe(t) === "PREVENTIVA" ? t.frecuencia : null,
    conjuntoId: t.conjunto?.id ?? null,
    conjunto: t.conjunto?.nombre ?? null,
    ubicacion: t.ubicacion?.nombre ?? null,
    elemento: t.elemento?.nombre ?? null,
    previstas: null,
    programadas: null,
    realizadasCronograma: null,
  });

  // 4) Actividades preventivas (incluye las previstas que nunca se programaron;
  // con filtros, solo las que tienen alguna tarea que los cumple).
  const preventivas = !tiposIncluidos.has("PREVENTIVA")
    ? []
    : Array.from(grupos.values())
        .filter((g) => !filtrado || g.tareas.length > 0)
        .map((g) =>
          construirActividad(
            "PREVENTIVA",
            {
              clave: g.clave,
              titulo: g.titulo,
              frecuencia: g.frecuencia,
              conjuntoId: g.conjuntoId,
              conjunto: null,
              ubicacion: g.ubicacion,
              elemento: g.elemento,
              previstas: g.previstas,
              programadas: g.programadas,
              realizadasCronograma: g.realizadasCronograma,
            },
            g.tareas,
            false,
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
      { ...baseDeTarea(t), clave: `correctiva:${t.id}` },
      [t],
      true,
    ),
  );

  // 5) Reemplazadas: con filtros, solo las que los cumplen (si se conoce la tarea).
  const idsEntrada = new Set(entrada.tareas.map((t) => t.id));
  const idsFiltradas = new Set(tareasFiltradas.map((t) => t.id));
  const estadosFiltro = opciones.filtros.estados
    ? new Set<string>(opciones.filtros.estados)
    : null;
  const reemplazoIncluido = (r: ReemplazoInforme): boolean => {
    if (!filtrado) return true;
    if (idsEntrada.has(r.tareaPreventivaId)) return idsFiltradas.has(r.tareaPreventivaId);
    if (!tiposIncluidos.has("PREVENTIVA")) return false;
    if (estadosFiltro && !estadosFiltro.has(String(r.estadoActual ?? "").toUpperCase())) {
      return false;
    }
    // Sin la tarea no se sabe su ubicacion, frecuencia ni evidencias.
    const f = opciones.filtros;
    return !(f.ubicaciones || f.frecuencias || f.soloConEvidencia);
  };

  const reemplazadas: TareaReemplazadaInforme[] = [];
  const vistas = new Set<number>();
  for (const r of entrada.reemplazos) {
    if (vistas.has(r.tareaPreventivaId)) continue;
    vistas.add(r.tareaPreventivaId);
    if (!reemplazoIncluido(r)) continue;
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

  // 6) Cuerpo segun la organizacion elegida.
  const secciones: SeccionInforme[] = [];
  if (opciones.secciones.detalle) {
    if (opciones.organizacion === "UBICACION") {
      const conjuntos = new Set(
        [...preventivas, ...correctivas].map((a) => a.conjuntoId ?? ""),
      );
      const varios = conjuntos.size > 1;
      const porUbicacion = new Map<string, { titulo: string; actividades: ActividadInforme[] }>();
      for (const a of [...preventivas, ...correctivas]) {
        const ubic = texto(a.ubicacion) || "Sin ubicación";
        const key = `${varios ? (a.conjuntoId ?? "") : ""}|${normalizarClave(ubic)}`;
        const nombre = varios && a.conjuntoId ? nombreConjunto.get(a.conjuntoId) : null;
        const slot = porUbicacion.get(key) ?? {
          titulo: nombre ? `${nombre} - ${ubic}` : ubic,
          actividades: [],
        };
        slot.actividades.push(a);
        porUbicacion.set(key, slot);
      }
      for (const g of Array.from(porUbicacion.values()).sort((a, b) =>
        a.titulo.localeCompare(b.titulo, "es"),
      )) {
        secciones.push({ tipo: "UBICACION", titulo: g.titulo, actividades: g.actividades });
      }
    } else if (opciones.organizacion === "CRONOLOGICO") {
      let actual: { clave: string; fecha: Date; actividades: ActividadInforme[] } | null = null;
      for (const t of ordenadas) {
        const clave = claveDia(t.fechaInicio);
        if (!actual || actual.clave !== clave) {
          actual = { clave, fecha: aFecha(t.fechaInicio), actividades: [] };
          secciones.push({ tipo: "DIA", fecha: actual.fecha, actividades: actual.actividades });
        }
        actual.actividades.push(construirActividad(tipoDe(t), baseDeTarea(t), [t], true));
      }
    } else {
      if (tiposIncluidos.has("PREVENTIVA")) {
        secciones.push({ tipo: "PREVENTIVAS", actividades: preventivas });
      }
      if (tiposIncluidos.has("CORRECTIVA")) {
        secciones.push({ tipo: "CORRECTIVAS", actividades: correctivas });
      }
    }
  }

  // 7) Tope de fotos de todo el informe (solo lo que se va a dibujar).
  const cuerpo = new Set<ActividadInforme>();
  for (const s of secciones) for (const a of s.actividades) cuerpo.add(a);
  const limite = limiteFotosInforme(opciones.fotos.calidad);
  const omitidasPorLimite = aplicarTopeFotos(Array.from(cuerpo), limite);
  const incluidas = Array.from(cuerpo).reduce((acc, a) => acc + a.fotos.length, 0);

  // 8) Secciones de soporte para auditoria.
  const cumplimiento: FilaCumplimiento[] = preventivas.map((a) => {
    const base = a.previstas != null ? a.previstas : a.baseRealizadas;
    return {
      titulo: a.titulo,
      frecuencia: a.frecuenciaEtiqueta,
      ubicacion: a.ubicacion,
      previstas: a.previstas,
      programadas: a.programadas,
      realizadas: a.realizadas,
      base,
      porcentaje: base > 0 ? Math.round((a.realizadas / base) * 100) : null,
    };
  });

  const ahora = (entrada.ahora ?? new Date()).getTime();
  const novedades: FilaNovedad[] = ordenadas
    .filter((t) => {
      const e = String(t.estado ?? "").toUpperCase();
      if (ESTADOS_NOVEDAD.has(e)) return true;
      return ESTADOS_ABIERTOS.has(e) && aFecha(t.fechaFin).getTime() < ahora;
    })
    .map((t) => {
      const e = String(t.estado ?? "").toUpperCase();
      return {
        tareaId: t.id,
        fecha: aFecha(t.fechaInicio),
        tipo: tipoDe(t),
        descripcion: t.descripcion,
        ubicacion: t.ubicacion?.nombre ?? null,
        estado: e,
        novedad: ESTADOS_ABIERTOS.has(e) ? "VENCIDA" : e,
        motivo: motivoNovedad(t, e, opciones.campos.motivoRechazo),
      };
    });

  const anexo: FilaAnexo[] = ordenadas.map((t) => ({
    tareaId: t.id,
    tipo: tipoDe(t),
    fecha: aFecha(t.fechaInicio),
    cierre: fechaOpcional(t.fechaFinalizarTarea),
    ubicacion: t.ubicacion?.nombre ?? null,
    descripcion: t.descripcion,
    estado: String(t.estado ?? "").toUpperCase(),
    responsables: unicos(t.operarios ?? []).join(", ") || texto(t.supervisor),
    evidencias: unicos(t.evidencias ?? []).length,
  }));

  // 9) Resumen general (de las tareas que entran en el informe).
  const porEstado = contarEstados(tareasFiltradas);
  const conCifras = preventivas.filter((a) => a.previstas != null);

  return {
    conjuntoNombre: entrada.conjuntoNombre,
    desde,
    hasta,
    resumen: {
      previstas: conCifras.reduce((acc, a) => acc + (a.previstas ?? 0), 0),
      programadas: conCifras.reduce((acc, a) => acc + (a.programadas ?? 0), 0),
      realizadas: conCifras.reduce((acc, a) => acc + a.realizadas, 0),
      hayCronograma: hayCronograma && conCifras.length > 0,
      totalTareas: tareasFiltradas.length,
      preventivas: tareasFiltradas.filter((t) => tipoDe(t) === "PREVENTIVA").length,
      correctivas: correctivasRaw.length,
      reemplazadas: reemplazadas.length,
      noCompletadas: porEstado.find((e) => e.estado === "NO_COMPLETADA")?.cantidad ?? 0,
      porEstado,
    },
    preventivas,
    correctivas,
    reemplazadas,
    opciones,
    filtrado,
    secciones,
    cumplimiento,
    novedades,
    consolidado: {
      insumos: consolidarRecursos(tareasFiltradas, "insumos"),
      maquinaria: consolidarRecursos(tareasFiltradas, "maquinaria"),
      herramientas: consolidarRecursos(tareasFiltradas, "herramientas"),
    },
    anexo,
    fotos: { incluidas, omitidasPorLimite, limite },
  };
}
