// src/utils/calendarioPlazaCore.ts
//
// Cálculo PURO (sin Prisma) del calendario día a día de una plaza
// (ConjuntoNecesidadOperario): para cada fecha, si es un día normal,
// festivo, descanso compensatorio o libre, y con qué horario (si alguno)
// trabaja la plaza ese día. Reemplaza la regla fija "SALVAVIDAS sí
// trabaja festivos" por una configuración por plaza (cualquier rol), y
// añade el descanso compensatorio automático que antes no existía.
//
// Se mantiene sin dependencias de Prisma a propósito: lo usan tanto
// `operarioAvailability.ts` (validación de horario efectivo en una fecha)
// como `calendarioPlaza.ts` (vistas de calendario para asistencia/reportes)
// sin crear un ciclo de imports entre ambos.
//
// Reglas:
// - Día de descanso semanal: cualquier día de la semana en que la plaza no
//   tiene horario (tipo LIBRE). No hay nada especial con el domingo: si la
//   plaza tiene horario el domingo, es un día de trabajo más.
// - Festivo: si la plaza tiene `trabajaFestivos`, usa su horario festivo
//   propio (obligatorio en ese caso); si no, el festivo es día no laborable
//   para esa plaza, sin importar el rol.
// - Descanso compensatorio: solo se genera cuando la plaza trabaja un festivo
//   que cae en su día de descanso semanal (o sea, trabajó el día que le
//   tocaba descansar). Un festivo que cae en un día que igual trabaja no
//   genera nada, y si no hubo festivo trabajado en el día de descanso, ese
//   sigue siendo su descanso normal. El compensatorio cae
//   `diasDescansoCompensatorio` días después; si ese día no es un día normal
//   de trabajo de la plaza (ya es descanso semanal, otro festivo trabajado
//   o ya es compensatorio de otro festivo), se corre al siguiente día NORMAL
//   (tope de 14 intentos).
import type { DiaSemana } from "@prisma/client";

import type { HorarioDia } from "./agenda";
import { dateToDiaSemana, ymdLocal } from "./schedulerUtils";

export type TipoDiaCalendarioPlaza =
  | "NORMAL"
  | "FESTIVO"
  | "DESCANSO"
  | "LIBRE";

export type DiaCalendarioPlaza = {
  tipo: TipoDiaCalendarioPlaza;
  /** Ventana de trabajo ese día, o null si la plaza no trabaja (LIBRE/DESCANSO/festivo sin trabajarFestivos). */
  horario: HorarioDia | null;
  /** Solo en tipo DESCANSO: fecha (ymd) del festivo trabajado que lo originó. */
  origen?: string;
  /**
   * Solo en tipo FESTIVO: true si el festivo cae en el día de descanso
   * semanal de la plaza (o sea, si lo trabaja, trabaja su día de descanso).
   */
  enDiaDeDescanso?: boolean;
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
 * días antes de `desde`, para que un festivo trabajado justo antes
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
    const horarioDia = horarioPorDia(dateToDiaSemana(f));
    if (festivos.has(key)) {
      base.set(key, {
        tipo: "FESTIVO",
        horario: horarioFestivo,
        enDiaDeDescanso: horarioDia == null,
      });
      continue;
    }
    base.set(key, {
      tipo: horarioDia ? "NORMAL" : "LIBRE",
      horario: horarioDia,
    });
  }

  // Segunda pasada: aplica el descanso compensatorio por encima de la base,
  // en orden cronológico. Un descanso corrido nunca origina otro descanso
  // (solo un festivo trabajado en el día de descanso semanal lo hace).
  const resultado = new Map<string, DiaCalendarioPlaza>(base);
  if (config.descansoCompensatorio) {
    for (let f = inicioCalculo; f.getTime() <= hasta.getTime(); f = addDays(f, 1)) {
      const key = ymdLocal(f);
      const diaBase = base.get(key);
      if (!diaBase) continue;
      const generaDescanso =
        diaBase.tipo === "FESTIVO" && diaBase.horario != null && diaBase.enDiaDeDescanso === true;
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
