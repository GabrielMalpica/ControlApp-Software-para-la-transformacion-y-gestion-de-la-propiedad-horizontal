// src/utils/ventanaRecurso.ts
import { calcularRangoReserva } from "./reservaMaquinaria";

/**
 * Ventanas de la agenda de recursos (ver docs/agenda-recursos.md).
 *
 * - uso: horas reales en que la tarea usa la unidad.
 * - bloqueo: ventana fisica en que la unidad queda comprometida con el conjunto.
 *
 * Regla hibrida:
 * - origen CONJUNTO (propia del conjunto o en custodia alli): bloqueo = uso.
 * - origen EMPRESA: la unidad viaja. Si la empresa tiene dias de entrega y
 *   recogida, se sale el dia de entrega anterior y vuelve el de recogida
 *   posterior (saltando festivos). Si no tiene dias configurados ("por horas"),
 *   bloqueo = uso ± margen de traslado.
 */
export type OrigenVentana = "CONJUNTO" | "EMPRESA";

export type ConfigLogisticaRecursos = {
  /** 0=domingo..6=sabado, igual que Date#getDay. Vacio = modo por horas. */
  diasEntregaRecursos: number[];
  margenTrasladoMinutos: number;
};

export const CONFIG_LOGISTICA_DEFAULT: ConfigLogisticaRecursos = {
  diasEntregaRecursos: [1, 3, 6],
  margenTrasladoMinutos: 0,
};

export type VentanaRecurso = {
  usoInicio: Date;
  usoFin: Date;
  bloqueoInicio: Date;
  bloqueoFin: Date;
};

const MINUTO_MS = 60_000;

/** Normaliza un rango de uso: nunca vacio (la BD exige usoFin > usoInicio). */
export function normalizarUso(inicio: Date, fin: Date): { usoInicio: Date; usoFin: Date } {
  if (!(inicio instanceof Date) || Number.isNaN(+inicio)) {
    throw new Error("Fecha de inicio de uso inválida.");
  }
  if (!(fin instanceof Date) || Number.isNaN(+fin)) {
    throw new Error("Fecha de fin de uso inválida.");
  }
  const usoInicio = +inicio <= +fin ? inicio : fin;
  let usoFin = +inicio <= +fin ? fin : inicio;
  if (+usoFin <= +usoInicio) usoFin = new Date(+usoInicio + MINUTO_MS);
  return { usoInicio: new Date(usoInicio), usoFin: new Date(usoFin) };
}

export function normalizarConfigLogistica(raw: {
  diasEntregaRecursos?: number[] | null;
  margenTrasladoMinutos?: number | null;
} | null | undefined): ConfigLogisticaRecursos {
  const dias = Array.isArray(raw?.diasEntregaRecursos)
    ? Array.from(
        new Set(
          raw!.diasEntregaRecursos!.filter(
            (d) => Number.isInteger(d) && d >= 0 && d <= 6,
          ),
        ),
      ).sort((a, b) => a - b)
    : CONFIG_LOGISTICA_DEFAULT.diasEntregaRecursos;
  const margen = Number(raw?.margenTrasladoMinutos ?? 0);
  return {
    diasEntregaRecursos: dias,
    margenTrasladoMinutos:
      Number.isFinite(margen) && margen > 0 ? Math.min(1440, Math.round(margen)) : 0,
  };
}

export function calcularVentanaRecurso(params: {
  origen: OrigenVentana;
  usoInicio: Date;
  usoFin: Date;
  config: ConfigLogisticaRecursos;
  festivosSet?: Set<string>;
}): VentanaRecurso {
  const { origen, config, festivosSet } = params;
  const { usoInicio, usoFin } = normalizarUso(params.usoInicio, params.usoFin);

  if (origen === "CONJUNTO") {
    return { usoInicio, usoFin, bloqueoInicio: usoInicio, bloqueoFin: usoFin };
  }

  if (config.diasEntregaRecursos.length > 0) {
    const rango = calcularRangoReserva({
      fechaInicioUso: usoInicio,
      fechaFinUso: usoFin,
      diasEntregaRecogida: new Set(config.diasEntregaRecursos),
      festivosSet,
    });
    return {
      usoInicio,
      usoFin,
      // El rango logistico siempre contiene al uso; min/max lo garantiza
      // aunque el uso cruce la medianoche del dia de recogida.
      bloqueoInicio: new Date(Math.min(+rango.iniReserva, +usoInicio)),
      bloqueoFin: new Date(Math.max(+rango.finReserva, +usoFin)),
    };
  }

  const margenMs = config.margenTrasladoMinutos * MINUTO_MS;
  return {
    usoInicio,
    usoFin,
    bloqueoInicio: new Date(+usoInicio - margenMs),
    bloqueoFin: new Date(+usoFin + margenMs),
  };
}

/** Rango semiabierto [a1,a2) ∩ [b1,b2) ≠ ∅ (igual que tsrange '[)' en la BD). */
export function rangosSeSolapan(a1: Date, a2: Date, b1: Date, b2: Date): boolean {
  return +a1 < +b2 && +b1 < +a2;
}

/**
 * Detecta la violacion de una restriccion de exclusion de ReservaRecurso.
 * Prisma la entrega como PrismaClientUnknownRequestError con el nombre de la
 * restriccion en el mensaje (no trae codigo P****).
 */
export function esErrorExclusionReserva(err: unknown): boolean {
  const msg = String((err as any)?.message ?? "");
  return (
    msg.includes("ReservaRecurso_maquinaria_uso_excl") ||
    msg.includes("ReservaRecurso_herramienta_uso_excl") ||
    msg.includes("ReservaRecurso_maquinaria_ubicacion_excl") ||
    msg.includes("ReservaRecurso_herramienta_ubicacion_excl") ||
    msg.includes("23P01")
  );
}

/** Rango [inicio, fin) de los dias que cubre una ventana (para consultar festivos). */
export function rangoConsultaFestivos(inicio: Date, fin: Date): { inicio: Date; fin: Date } {
  return {
    inicio: new Date(inicio.getFullYear(), inicio.getMonth(), inicio.getDate() - 14),
    fin: new Date(fin.getFullYear(), fin.getMonth(), fin.getDate() + 14),
  };
}
