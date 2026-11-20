export const FASES_PLAN_ESPERANZA = [
  { clave: "DIAGNOSTICO", nombre: "Diagnóstico", mesBase: 1 },
  { clave: "RECUPERACION", nombre: "Recuperación", mesBase: 3 },
  { clave: "CONTROL", nombre: "Control", mesBase: 6 },
  { clave: "PREVENCION", nombre: "Prevención", mesBase: 9 },
  { clave: "CIERRE_RENOVACION", nombre: "Cierre para renovación", mesBase: -1 },
  { clave: "INFORME_ANUAL", nombre: "Informe anual", mesBase: 0 },
] as const;

export type FasePlanClave = (typeof FASES_PLAN_ESPERANZA)[number]["clave"];

export type FaseProgramada = {
  clave: FasePlanClave;
  nombre: string;
  mesObjetivo: number;
  fechaProgramada: Date;
};

function inicioMesUtc(fecha: Date, desplazamiento: number): Date {
  return new Date(Date.UTC(fecha.getUTCFullYear(), fecha.getUTCMonth() + desplazamiento, 1));
}

export function inicioMesEnBogota(fecha = new Date()): Date {
  const partes = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bogota",
    year: "numeric",
    month: "2-digit",
  }).formatToParts(fecha);
  const año = Number(partes.find((parte) => parte.type === "year")?.value);
  const mes = Number(partes.find((parte) => parte.type === "month")?.value);
  return new Date(Date.UTC(año, mes - 1, 1));
}

export function contarMesesContrato(inicio: Date, fin: Date): number {
  return Math.max(
    1,
    (fin.getUTCFullYear() - inicio.getUTCFullYear()) * 12 +
      fin.getUTCMonth() -
      inicio.getUTCMonth() +
      1,
  );
}

export function programarFasesPlanEsperanza(inicio: Date, fin: Date): FaseProgramada[] {
  const totalMeses = contarMesesContrato(inicio, fin);
  let mesAnterior = 1;
  return FASES_PLAN_ESPERANZA.map((fase) => {
    const solicitado =
      fase.mesBase === -1 ? totalMeses - 1 : fase.mesBase === 0 ? totalMeses : fase.mesBase;
    const mesObjetivo = Math.min(totalMeses, Math.max(mesAnterior, solicitado));
    mesAnterior = mesObjetivo;
    return {
      clave: fase.clave,
      nombre: fase.nombre,
      mesObjetivo,
      fechaProgramada: inicioMesUtc(inicio, mesObjetivo - 1),
    };
  });
}

export function sumarAnnosContrato(fecha: Date, annos: number): Date {
  const mes = fecha.getUTCMonth();
  const dia = fecha.getUTCDate();
  const ultimoDiaMes = new Date(Date.UTC(fecha.getUTCFullYear() + annos, mes + 1, 0)).getUTCDate();
  return new Date(Date.UTC(fecha.getUTCFullYear() + annos, mes, Math.min(dia, ultimoDiaMes)));
}

export function construirRangosContrato(inicio: Date, fin?: Date | null, hoy = new Date()) {
  const proximoCierre = new Date(sumarAnnosContrato(inicio, 1).getTime() - 24 * 60 * 60 * 1000);
  const limite = fin ?? (inicio > hoy ? proximoCierre : hoy);
  const rangos: Array<{ inicio: Date; fin: Date }> = [];
  for (let annos = 0; annos < 80; annos += 1) {
    const inicioCiclo = sumarAnnosContrato(inicio, annos);
    if (inicioCiclo > limite) break;
    const aniversarioSiguiente = sumarAnnosContrato(inicio, annos + 1);
    const finCicloNatural = new Date(aniversarioSiguiente.getTime() - 24 * 60 * 60 * 1000);
    const finCiclo = fin && fin < finCicloNatural ? fin : finCicloNatural;
    rangos.push({ inicio: inicioCiclo, fin: finCiclo });
  }
  return rangos;
}
