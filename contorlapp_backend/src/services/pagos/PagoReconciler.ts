import type { PagoService } from "./PagoService";

// Cada cuanto revisa la cola de cobros pendientes (no cada cuanto se
// reconsulta UN cobro: eso lo decide backoff.ts segun su antiguedad).
const INTERVALO_MS = Number(process.env.PAGOS_WORKER_INTERVALO_MS ?? 5_000);
const LOTE = Number(process.env.PAGOS_WORKER_LOTE ?? 20);

let intervalo: NodeJS.Timeout | null = null;
let corriendo = false;

function workerHabilitado() {
  return String(process.env.PAGOS_WORKER_ENABLED ?? "true").trim().toLowerCase() !== "false";
}

/**
 * Arranca el worker que mantiene al dia los cobros de Factus (equivalente al
 * webhook que Factus no ofrece). Se llama una sola vez desde index.ts, junto
 * al resto de tareas de arranque. Devuelve la funcion para detenerlo (util
 * en tests y en un apagado limpio).
 */
export function iniciarPagoReconciler(pagoService: PagoService): () => void {
  if (!workerHabilitado()) {
    console.warn("[pagos] worker de conciliacion deshabilitado (PAGOS_WORKER_ENABLED=false)");
    return () => {};
  }
  if (intervalo) return detenerPagoReconciler;

  const vuelta = async () => {
    // Si una vuelta tarda mas que el intervalo (lote grande, Factus lento),
    // se salta la siguiente en vez de superponerse.
    if (corriendo) return;
    corriendo = true;
    try {
      await pagoService.procesarPendientes(LOTE);
    } catch (error) {
      console.error("[pagos] fallo una vuelta del worker de conciliacion", {
        name: error instanceof Error ? error.name : "Error",
      });
    } finally {
      corriendo = false;
    }
  };

  intervalo = setInterval(() => void vuelta(), INTERVALO_MS);
  intervalo.unref?.();
  return detenerPagoReconciler;
}

export function detenerPagoReconciler() {
  if (intervalo) {
    clearInterval(intervalo);
    intervalo = null;
  }
  corriendo = false;
}

let intervaloConciliacion: NodeJS.Timeout | null = null;

/**
 * Conciliacion periodica (por defecto cada 24 h, PAGOS_CONCILIACION_HORAS; 0
 * la apaga): compara lo que Factus lista como pagado con los cobros locales.
 * `ultima` devuelve la fecha de la ultima corrida -compartida entre
 * instancias- para que solo una la ejecute por periodo.
 */
export function iniciarConciliacionPeriodica(deps: {
  ejecutar: () => Promise<unknown>;
  ultima: () => Promise<Date | null>;
}): () => void {
  const horas = Number(process.env.PAGOS_CONCILIACION_HORAS ?? 24);
  if (!workerHabilitado() || !(horas > 0)) return () => {};
  if (intervaloConciliacion) return detenerConciliacionPeriodica;

  let corriendoConciliacion = false;
  const revisar = async () => {
    if (corriendoConciliacion) return;
    corriendoConciliacion = true;
    try {
      const ultima = await deps.ultima();
      if (ultima && Date.now() - ultima.getTime() < horas * 3_600_000) return;
      await deps.ejecutar();
    } catch (error) {
      console.error("[pagos] fallo la conciliacion periodica", {
        name: error instanceof Error ? error.name : "Error",
      });
    } finally {
      corriendoConciliacion = false;
    }
  };
  // Se revisa cada 30 min si toca, y una vez poco despues de arrancar.
  const inicial = setTimeout(() => void revisar(), 2 * 60_000);
  inicial.unref?.();
  intervaloConciliacion = setInterval(() => void revisar(), 30 * 60_000);
  intervaloConciliacion.unref?.();
  return detenerConciliacionPeriodica;
}

export function detenerConciliacionPeriodica() {
  if (intervaloConciliacion) {
    clearInterval(intervaloConciliacion);
    intervaloConciliacion = null;
  }
}
