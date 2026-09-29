const MINUTO = 60_000;
const HORA = 3_600_000;
const DIA = 86_400_000;

/** Tras cuanto tiempo abandonar la verificacion activa de un cobro (sigue
 * cubierto por la conciliacion periodica de la fase 5, no por este worker). */
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
