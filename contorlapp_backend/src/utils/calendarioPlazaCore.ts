// src/utils/calendarioPlazaCore.ts
//
// Cálculo PURO (sin Prisma) del calendario día a día de una plaza
// (ConjuntoNecesidadOperario): para cada fecha, si es un día normal,
// festivo, domingo, descanso compensatorio o libre, y con qué horario (si
// alguno) trabaja la plaza ese día. Reemplaza la regla fija "SALVAVIDAS sí
// trabaja festivos" por una configuración por plaza (cualquier rol), y
// añade el descanso compensatorio automático que antes no existía.
//
// Se mantiene sin dependencias de Prisma a propósito: lo usan tanto
// `operarioAvailability.ts` (validación de horario efectivo en una fecha)
// como `calendarioPlaza.ts` (vistas de calendario para asistencia/reportes)
// sin crear un ciclo de imports entre ambos.
//
// Reglas (ver plan "Festivos y descanso compensatorio en las plazas"):
// - Festivo: si la plaza tiene `trabajaFestivos`, usa su horario festivo
//   propio (obligatorio en ese caso); si no, el festivo es día no laborable
//   para esa plaza, sin importar el rol. El festivo tiene precedencia sobre
//   el domingo (un festivo en domingo se resuelve como festivo).
// - Domingo (que no sea festivo): "trabajado" si el horario por día de la
//   plaza para DOMINGO no es null (comportamiento ya existente).
// - Descanso compensatorio: si la plaza lo tiene activo, un festivo o
//   domingo TRABAJADO genera un día de descanso `diasDescansoCompensatorio`
//   días después. Si ese día cae en otro festivo, domingo trabajado, un día
//   que la plaza no trabaja, o ya es descanso de otro festivo/domingo, se
//   corre al siguiente día que sería NORMAL para la plaza (tope de 14
//   intentos).
import { DiaSemana as DiaSemanaEnum, type DiaSemana } from "@prisma/client";

import type { HorarioDia } from "./agenda";
import { dateToDiaSemana, ymdLocal } from "./schedulerUtils";

export type TipoDiaCalendarioPlaza =
  | "NORMAL"
  | "FESTIVO"
  | "DOMINGO"
  | "DESCANSO"
  | "LIBRE";

export type DiaCalendarioPlaza = {
  tipo: TipoDiaCalendarioPlaza;
  /** Ventana de trabajo ese día, o null si la plaza no trabaja (LIBRE/DESCANSO/festivo sin trabajarFestivos). */
  horario: HorarioDia | null;
  /** Solo en tipo DESCANSO: fecha (ymd) del festivo/domingo que lo originó. */
  origen?: string;
};

export type ConfigFestivoNecesidad = {
  trabajaFestivos: boolean;
  festivoHoraApertura: string | null;
  festivoHoraCierre: string | null;
  festivoDescansoInicio: string | null;
  festivoDescansoFin: string | null;
  descansoCompensatorio: boolean;
  diasDescansoCompensatorio: number;
};

export const CONFIG_FESTIVO_DEFAULT: ConfigFestivoNecesidad = {
  trabajaFestivos: false,
  festivoHoraApertura: null,
  festivoHoraCierre: null,
  festivoDescansoInicio: null,
  festivoDescansoFin: null,
  descansoCompensatorio: false,
  diasDescansoCompensatorio: 1,
};

function parseHoraMin(value: string | null | undefined): number | null {
  if (!value) return null;
  const match = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!match) return null;
  const h = Number(match[1]);
  const m = Number(match[2]);
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return h * 60 + m;
}

function horarioFestivoDe(config: ConfigFestivoNecesidad): HorarioDia | null {
  const startMin = parseHoraMin(config.festivoHoraApertura);
  const endMin = parseHoraMin(config.festivoHoraCierre);
  if (startMin == null || endMin == null || endMin <= startMin) return null;
  return {
    startMin,
    endMin,
    descansoStartMin: parseHoraMin(config.festivoDescansoInicio) ?? undefined,
    descansoEndMin: parseHoraMin(config.festivoDescansoFin) ?? undefined,
  };
}

function addDays(fecha: Date, dias: number): Date {
  const x = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
  x.setDate(x.getDate() + dias);
  return x;
}

export const MARGEN_DIAS_ARRASTRE_CALENDARIO = 21;
const MAX_INTENTOS_CORRIDA = 14;

/**
 * Calendario día a día de UNA plaza entre `desde` y `hasta` (ambos
 * inclusive). Internamente calcula desde `MARGEN_DIAS_ARRASTRE_CALENDARIO`
 * días antes de `desde`, para que un festivo/domingo trabajado justo antes
 * del rango pedido siga generando su descanso compensatorio dentro de él
 * (p.ej. un festivo el último día de un mes genera el descanso el día 1 del
 * siguiente).
 */
export function calcularCalendarioPlaza(params: {
  desde: Date;
  hasta: Date;
  festivos: Set<string>;
  horarioPorDia: (dia: DiaSemana) => HorarioDia | null;
  config: ConfigFestivoNecesidad;
}): Map<string, DiaCalendarioPlaza> {
  const { desde, hasta, festivos, horarioPorDia, config } = params;
  const horarioFestivo = config.trabajaFestivos ? horarioFestivoDe(config) : null;

  const inicioCalculo = addDays(desde, -MARGEN_DIAS_ARRASTRE_CALENDARIO);

  // Primera pasada: tipo/horario "base" de cada día, sin descansos aún.
  const base = new Map<string, DiaCalendarioPlaza>();
  for (let f = inicioCalculo; f.getTime() <= hasta.getTime(); f = addDays(f, 1)) {
    const key = ymdLocal(f);
    if (festivos.has(key)) {
      base.set(key, { tipo: "FESTIVO", horario: horarioFestivo });
      continue;
    }
    const horarioDia = horarioPorDia(dateToDiaSemana(f));
    const esDomingo = dateToDiaSemana(f) === DiaSemanaEnum.DOMINGO;
    base.set(key, {
      tipo: horarioDia ? (esDomingo ? "DOMINGO" : "NORMAL") : "LIBRE",
      horario: horarioDia,
    });
  }

  // Segunda pasada: aplica el descanso compensatorio por encima de la base,
  // en orden cronológico. Un descanso corrido nunca origina otro descanso
  // (solo un festivo/domingo "base" trabajado lo hace).
  const resultado = new Map<string, DiaCalendarioPlaza>(base);
  if (config.descansoCompensatorio) {
    for (let f = inicioCalculo; f.getTime() <= hasta.getTime(); f = addDays(f, 1)) {
      const key = ymdLocal(f);
      const diaBase = base.get(key);
      if (!diaBase) continue;
      const generaDescanso =
        (diaBase.tipo === "FESTIVO" || diaBase.tipo === "DOMINGO") && diaBase.horario != null;
      if (!generaDescanso) continue;

      let candidato = addDays(f, config.diasDescansoCompensatorio);
      for (let intento = 0; intento < MAX_INTENTOS_CORRIDA; intento++) {
        const candidatoKey = ymdLocal(candidato);
        const candidatoBase = base.get(candidatoKey);
        if (!candidatoBase) break; // fuera de la ventana calculada
        const yaAsignado = resultado.get(candidatoKey)?.tipo === "DESCANSO";
        const esLaborableNormal = candidatoBase.tipo === "NORMAL" && candidatoBase.horario != null;
        if (!yaAsignado && esLaborableNormal) {
          resultado.set(candidatoKey, { tipo: "DESCANSO", horario: null, origen: key });
          break;
        }
        candidato = addDays(candidato, 1);
      }
    }
  }

  // Solo se devuelve el rango pedido; los días de arrastre previos a `desde`
  // solo servían para resolver bien los descansos que empiezan ahí.
  const salida = new Map<string, DiaCalendarioPlaza>();
  for (let f = new Date(desde); f.getTime() <= hasta.getTime(); f = addDays(f, 1)) {
    const key = ymdLocal(f);
    const dia = resultado.get(key);
    if (dia) salida.set(key, dia);
  }
  return salida;
}
