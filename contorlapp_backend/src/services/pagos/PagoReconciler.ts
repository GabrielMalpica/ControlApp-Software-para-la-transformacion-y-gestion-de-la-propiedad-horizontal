import { detalleErrorPagos } from "./errors";
import { isFactusPayConfigured } from "./FactusPayClient";
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

let avisoSinConfigurar = false;

/** Sin credenciales de Factus no hay nada que verificar ni conciliar: se
 * avisa una sola vez al arrancar en vez de fallar cada vuelta. */
function factusDisponible(): boolean {
  if (isFactusPayConfigured()) return true;
  if (!avisoSinConfigurar) {
    avisoSinConfigurar = true;
    console.warn("[pagos] Factus Pay sin configurar (FACTUS_PAY_*): no se verifican ni concilian cobros");
  }
  return false;
}

/**
 * Arranca el worker que mantiene al dia los cobros de Factus: consulta los
 * pendientes segun su calendario, retoma los avisos del webhook que quedaron
 * sin procesar (`barrerWebhooks`) y revisa si el webhook esta llegando
 * (`evaluarSalud`, que elige entre el modo webhook y el sondeo frecuente). Se llama una sola vez desde index.ts,
 * junto al resto de tareas de arranque. Devuelve la funcion para detenerlo
 * (util en tests y en un apagado limpio).
 */
export function iniciarPagoReconciler(
  pagoService: PagoService,
  deps: { barrerWebhooks?: () => Promise<unknown>; evaluarSalud?: () => Promise<unknown> } = {},
): () => void {
  if (!workerHabilitado()) {
    console.warn("[pagos] worker de conciliacion deshabilitado (PAGOS_WORKER_ENABLED=false)");
    return () => {};
  }
  if (!factusDisponible()) return () => {};
  if (intervalo) return detenerPagoReconciler;

  const vuelta = async () => {
    // Si una vuelta tarda mas que el intervalo (lote grande, Factus lento),
    // se salta la siguiente en vez de superponerse.
    if (corriendo) return;
    corriendo = true;
    try {
      await pagoService.procesarPendientes(LOTE);
    } catch (error) {
      console.error("[pagos] fallo una vuelta del worker de conciliacion", detalleErrorPagos(error));
    }
    try {
      await deps.barrerWebhooks?.();
    } catch (error) {
      console.error("[pagos] fallo el barrido de avisos de Factus", detalleErrorPagos(error));
    }
    try {
      // Decide si el webhook esta llegando (modo webhook o sondeo frecuente).
      await deps.evaluarSalud?.();
    } catch (error) {
      console.error("[pagos] fallo la revision de salud del webhook", detalleErrorPagos(error));
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
let inicialConciliacion: NodeJS.Timeout | null = null;

/** Tras un fallo no se reintenta cada 30 min (llenaba el log con el mismo
 * error todo el dia): se espera esto, o el periodo si es menor. */
const ESPERA_TRAS_FALLO_MS = 6 * 3_600_000;

/**
 * Conciliacion periodica (por defecto cada 24 h, PAGOS_CONCILIACION_HORAS; 0
 * la apaga): compara lo que Factus lista como pagado con los cobros locales.
 * `ultima` devuelve la fecha de la ultima corrida -compartida entre
 * instancias- para que solo una la ejecute por periodo.
 */
export function iniciarConciliacionPeriodica(deps: {
  ejecutar: () => Promise<unknown>;
  ultima: () => Promise<Date | null>;
  /** Para pruebas: por defecto, que FACTUS_PAY_* este configurado. */
  disponible?: () => boolean;
}): () => void {
  const horas = Number(process.env.PAGOS_CONCILIACION_HORAS ?? 24);
  if (!workerHabilitado() || !(horas > 0)) return () => {};
  if (!(deps.disponible ?? factusDisponible)()) return () => {};
  if (intervaloConciliacion) return detenerConciliacionPeriodica;

  const periodoMs = horas * 3_600_000;
  let corriendoConciliacion = false;
  let reintentarDesde = 0;
  let fallosSeguidos = 0;
  const revisar = async () => {
    if (corriendoConciliacion || Date.now() < reintentarDesde) return;
    corriendoConciliacion = true;
    try {
      const ultima = await deps.ultima();
      if (ultima && Date.now() - ultima.getTime() < periodoMs) return;
      await deps.ejecutar();
      if (fallosSeguidos > 0) {
        console.info(`[pagos] la conciliacion periodica volvio a funcionar tras ${fallosSeguidos} fallo(s)`);
      }
      fallosSeguidos = 0;
    } catch (error) {
      fallosSeguidos++;
      const esperaMs = Math.min(periodoMs, ESPERA_TRAS_FALLO_MS);
      reintentarDesde = Date.now() + esperaMs;
      console.error("[pagos] fallo la conciliacion periodica", {
        ...detalleErrorPagos(error),
        fallosSeguidos,
        reintentoEnHoras: Math.round((esperaMs / 3_600_000) * 10) / 10,
      });
    } finally {
      corriendoConciliacion = false;
    }
  };
  // Se revisa cada 30 min si toca, y una vez poco despues de arrancar.
  inicialConciliacion = setTimeout(() => void revisar(), 2 * 60_000);
  inicialConciliacion.unref?.();
  intervaloConciliacion = setInterval(() => void revisar(), 30 * 60_000);
  intervaloConciliacion.unref?.();
  return detenerConciliacionPeriodica;
}

export function detenerConciliacionPeriodica() {
  if (inicialConciliacion) {
    clearTimeout(inicialConciliacion);
    inicialConciliacion = null;
  }
  if (intervaloConciliacion) {
    clearInterval(intervaloConciliacion);
    intervaloConciliacion = null;
  }
}
