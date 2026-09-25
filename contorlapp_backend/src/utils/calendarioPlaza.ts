// src/utils/calendarioPlaza.ts
//
// Punto de entrada público para el calendario de festivos/descanso
// compensatorio de una plaza (ConjuntoNecesidadOperario): lo usan
// AsistenciaService, ReporteService y el endpoint de calendario de
// necesidades. El cálculo puro vive en `calendarioPlazaCore.ts` y las
// consultas Prisma (config por plaza, resolución de horarios) en
// `operarioAvailability.ts` -que ya las necesita internamente para validar
// intervalos de programación-; este archivo solo las reexporta para que el
// resto del código no tenga que saber dónde vive cada pieza.
export {
  calcularCalendarioPlaza,
  CONFIG_FESTIVO_DEFAULT,
  type ConfigFestivoNecesidad,
  type DiaCalendarioPlaza,
  type TipoDiaCalendarioPlaza,
} from "./calendarioPlazaCore";

export {
  obtenerConfigFestivoNecesidades,
  operariosPuedenTrabajarFestivo,
  obtenerCalendariosOperarios,
} from "./operarioAvailability";
