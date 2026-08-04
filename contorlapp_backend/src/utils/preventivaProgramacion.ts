import { DiaSemana, Frecuencia } from "@prisma/client";

export type ProgramacionFrecuencia = {
  frecuencia: Frecuencia;
  diaSemanaProgramado?: DiaSemana | null;
  diaMesProgramado?: number | null;
  fechasProgramadasJson?: string[] | null;
};

export function fechasRequeridasPorFrecuencia(
  frecuencia: Frecuencia,
): number | null {
  switch (frecuencia) {
    case Frecuencia.BIMESTRAL:
      return 2;
    case Frecuencia.TRIMESTRAL:
      return 3;
    case Frecuencia.SEMESTRAL:
      return 2;
    case Frecuencia.ANUAL:
      return 1;
    default:
      return null;
  }
}

export function validarProgramacionFrecuencia(
  params: ProgramacionFrecuencia,
): void {
  const {
    frecuencia,
    diaSemanaProgramado,
    diaMesProgramado,
    fechasProgramadasJson,
  } = params;

  if (frecuencia === Frecuencia.SEMANAL && !diaSemanaProgramado) {
    throw new Error("Las preventivas semanales deben tener un día programado.");
  }
  if (frecuencia === Frecuencia.QUINCENAL && !diaSemanaProgramado) {
    throw new Error(
      "Las preventivas quincenales deben tener un día de la semana programado.",
    );
  }
  if (frecuencia === Frecuencia.MENSUAL && !diaMesProgramado) {
    throw new Error("Las preventivas mensuales deben tener un día del mes programado.");
  }

  const requeridas = fechasRequeridasPorFrecuencia(frecuencia);
  if (requeridas == null) return;

  const fechas = fechasProgramadasJson ?? [];
  const unicas = new Set(fechas);
  if (unicas.size !== fechas.length) {
    throw new Error("Las fechas programadas no pueden estar repetidas.");
  }
  if (fechas.length < requeridas) {
    throw new Error(
      `Faltan ${requeridas - fechas.length} fecha(s) para completar la frecuencia ${frecuencia}.`,
    );
  }
  if (fechas.length > requeridas) {
    throw new Error(
      `No puedes registrar más de ${requeridas} fecha(s) para la frecuencia ${frecuencia}.`,
    );
  }
}
