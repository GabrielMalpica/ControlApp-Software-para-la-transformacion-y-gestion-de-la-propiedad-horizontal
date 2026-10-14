const MINUTO = 60_000;
const HORA = 3_600_000;
const DIA = 86_400_000;

/** Tras cuanto tiempo abandonar la verificacion activa de un cobro en el modo
 * de sondeo (sigue cubierto por la conciliacion periodica, no por el worker). */
export const ABANDONO_MS = 7 * DIA;

/**
 * Cuanto esperar antes de volver a consultar un cobro en Factus, segun su
 * antiguedad (no segun cuantas veces ya se consulto: reintentar tras un
 * error usa la misma escala, ver PagoService.registrarFalloConsulta).
 *
 * null = ya paso el plazo razonable (7 dias): se abandona la verificacion
 * activa.
 */
export function siguienteEsperaMs(edadMs: number): number | null {
  if (edadMs < 0) return 10_000;
  if (edadMs < 5 * MINUTO) return 10_000;
  if (edadMs < 30 * MINUTO) return 30_000;
  if (edadMs < 24 * HORA) return 5 * MINUTO;
  if (edadMs < ABANDONO_MS) return HORA;
  return null;
}

/** Vigencia del QR cuando Factus no informa `qr_expires_at` (FAQ de Factus: 24 h). */
export const VIGENCIA_QR_POR_DEFECTO_MS = 24 * HORA;
// Consultas de respaldo cuando el webhook es la via principal: si el aviso
// no llego (endpoint caido mas de lo que Factus reintenta, llave
// desalineada), estas lo detectan.
const HITOS_WEBHOOK_MS = [15 * MINUTO, HORA, 6 * HORA];
// Ultima consulta: un poco despues de que vence el QR (ya no se puede pagar).
const MARGEN_TRAS_VENCER_MS = 15 * MINUTO;

/**
 * Calendario de respaldo con el webhook activo: unas 4 consultas por cobro
 * (a los 15 min, 1 h, 6 h y 15 min despues de vencer el QR) en vez de las
 * ~500 de siguienteEsperaMs. `vigenciaMs` = cuanto dura el QR desde que se
 * creo el cobro. null = ya paso la ultima consulta: se abandona (la
 * conciliacion diaria y el propio webhook siguen cubriendo un pago tardio).
 */
export function siguienteEsperaWebhookMs(edadMs: number, vigenciaMs: number): number | null {
  const ultima = Math.max(vigenciaMs, 0) + MARGEN_TRAS_VENCER_MS;
  const hitos = [...HITOS_WEBHOOK_MS.filter((hito) => hito < ultima), ultima];
  const proximo = hitos.find((hito) => hito > edadMs);
  return proximo == null ? null : proximo - edadMs;
}
