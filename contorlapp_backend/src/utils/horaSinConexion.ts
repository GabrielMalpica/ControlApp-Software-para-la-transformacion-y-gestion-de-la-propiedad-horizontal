// src/utils/horaSinConexion.ts
//
// Hora de lo que el operario hizo sin senal (cierres, fotos, asistencia) y que
// llega al servidor horas o dias despues. La app manda tres datos:
//
// - la hora del reloj del celular cuando paso (puede estar mal puesta),
// - una hora "estimada" calculada con el reloj monotonico del celular desde la
//   ultima respuesta del servidor (no cambia si alguien mueve la hora; se
//   pierde si el celular se reinicio),
// - la hora del reloj del celular al enviar, para medir cuanto esta corrido.
//
// Con eso se decide la hora oficial y si hubo que corregirla.

/** Diferencias menores a esto se consideran el mismo reloj. */
export const TOLERANCIA_RELOJ_MS = 5 * 60_000;
/** Una hora mas adelantada que esto respecto al servidor no es creible. */
export const MAX_FUTURO_MS = 10 * 60_000;
/** Ni el desfase del reloj ni una hora se aceptan mas alla de esto. */
const MAX_DESFASE_ABSURDO_MS = 2 * 365 * 86_400_000;

export type MotivoAjusteHora = "ESTIMADA" | "DESFASE" | "FUTURO";

export type HoraResuelta = {
  hora: Date | null;
  ajustada: boolean;
  motivo?: MotivoAjusteHora;
};

/** Fecha de un campo de texto o null si no se puede leer. */
export function parsearFecha(valor: unknown): Date | null {
  if (valor instanceof Date) return Number.isFinite(valor.getTime()) ? valor : null;
  if (typeof valor !== "string" || !valor.trim()) return null;
  const fecha = new Date(valor.trim());
  return Number.isFinite(fecha.getTime()) ? fecha : null;
}

/**
 * Cuanto esta corrido el reloj del celular respecto al del servidor, en ms
 * (positivo: el celular esta atrasado). Null si no vino o es absurdo.
 */
export function desfaseRelojMs(horaDispositivoEnvio: unknown, recibidoEn: Date): number | null {
  const enviada = parsearFecha(horaDispositivoEnvio);
  if (!enviada) return null;
  const desfase = recibidoEn.getTime() - enviada.getTime();
  return Math.abs(desfase) > MAX_DESFASE_ABSURDO_MS ? null : desfase;
}

/**
 * Hora oficial de algo hecho en el celular.
 *
 * 1. Si hay hora estimada (reloj monotonico) y difiere de la del celular mas
 *    de la tolerancia, gana la estimada: alguien movio el reloj o estaba mal.
 * 2. Si no hay estimada pero el reloj del celular estaba corrido al enviar,
 *    se corrige la hora por ese mismo desfase.
 * 3. Nunca queda en el futuro: lo que pase de la tolerancia se lleva a la
 *    hora en que llego.
 */
export function resolverHora(params: {
  hora: Date | null;
  horaEstimada?: Date | null;
  desfaseMs?: number | null;
  recibidoEn: Date;
}): HoraResuelta {
  const { recibidoEn } = params;
  const estimada =
    params.horaEstimada &&
    params.horaEstimada.getTime() <= recibidoEn.getTime() + MAX_FUTURO_MS &&
    recibidoEn.getTime() - params.horaEstimada.getTime() <= MAX_DESFASE_ABSURDO_MS
      ? params.horaEstimada
      : null;

  let hora = params.hora;
  let ajustada = false;
  let motivo: MotivoAjusteHora | undefined;

  if (!hora) {
    if (!estimada) return { hora: null, ajustada: false };
    hora = estimada;
  } else if (estimada && Math.abs(estimada.getTime() - hora.getTime()) > TOLERANCIA_RELOJ_MS) {
    hora = estimada;
    ajustada = true;
    motivo = "ESTIMADA";
  } else if (
    !estimada &&
    params.desfaseMs != null &&
    Math.abs(params.desfaseMs) > TOLERANCIA_RELOJ_MS
  ) {
    hora = new Date(hora.getTime() + params.desfaseMs);
    ajustada = true;
    motivo = "DESFASE";
  }

  if (hora.getTime() > recibidoEn.getTime() + MAX_FUTURO_MS) {
    return { hora: new Date(recibidoEn.getTime()), ajustada: true, motivo: "FUTURO" };
  }
  return motivo ? { hora, ajustada, motivo } : { hora, ajustada };
}

/** "true"/"1"/true del multipart o del JSON. */
export function esVerdadero(valor: unknown): boolean {
  if (valor === true) return true;
  if (typeof valor !== "string") return false;
  return ["true", "1", "si", "sí"].includes(valor.trim().toLowerCase());
}
