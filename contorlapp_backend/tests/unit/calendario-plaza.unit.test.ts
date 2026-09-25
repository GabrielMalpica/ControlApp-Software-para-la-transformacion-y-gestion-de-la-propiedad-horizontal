import { DiaSemana } from "@prisma/client";
import {
  calcularCalendarioPlaza,
  CONFIG_FESTIVO_DEFAULT,
  type ConfigFestivoNecesidad,
} from "../../src/utils/calendarioPlazaCore";
import type { HorarioDia } from "../../src/utils/agenda";

const HORARIO: HorarioDia = { startMin: 7 * 60, endMin: 16 * 60 };

const DIAS_LV: DiaSemana[] = [
  DiaSemana.LUNES,
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
];
const DIAS_MA_DO: DiaSemana[] = [
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
  DiaSemana.SABADO,
  DiaSemana.DOMINGO,
];

// L-V: descansa sábado y domingo.
const horarioPorDiaLV = (dia: DiaSemana): HorarioDia | null =>
  DIAS_LV.includes(dia) ? HORARIO : null;
// Martes a domingo: descansa el lunes.
const horarioPorDiaMaDo = (dia: DiaSemana): HorarioDia | null =>
  DIAS_MA_DO.includes(dia) ? HORARIO : null;

function config(overrides: Partial<ConfigFestivoNecesidad> = {}): ConfigFestivoNecesidad {
  return { ...CONFIG_FESTIVO_DEFAULT, ...overrides };
}

const CON_FESTIVOS = {
  trabajaFestivos: true,
  festivoHoraApertura: "09:00",
  festivoHoraCierre: "15:00",
} as const;

describe("calcularCalendarioPlaza", () => {
  test("festivo sin trabajaFestivos: la plaza no trabaja ese día", () => {
    // 2026-04-01 es miércoles.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 1),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config(),
    });
    expect(cal.get("2026-04-01")).toMatchObject({ tipo: "FESTIVO", horario: null });
  });

  test("festivo con trabajaFestivos usa el horario festivo propio", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 1),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config(CON_FESTIVOS),
    });
    expect(cal.get("2026-04-01")).toMatchObject({
      tipo: "FESTIVO",
      horario: { startMin: 9 * 60, endMin: 15 * 60 },
      enDiaDeDescanso: false,
    });
  });

  test("un domingo con horario es un día de trabajo normal (sin trato especial)", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(),
      horarioPorDia: horarioPorDiaMaDo,
      config: config(),
    });
    expect(cal.get("2026-08-23")).toEqual({ tipo: "NORMAL", horario: HORARIO });
  });

  test("un día sin horario queda LIBRE (día de descanso semanal)", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(),
      horarioPorDia: horarioPorDiaLV,
      config: config(),
    });
    expect(cal.get("2026-08-23")).toEqual({ tipo: "LIBRE", horario: null });
  });

  test("festivo que cae en el día de descanso semanal queda marcado enDiaDeDescanso", () => {
    // Domingo 2026-08-23, plaza L-V.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(["2026-08-23"]),
      horarioPorDia: horarioPorDiaLV,
      config: config(CON_FESTIVOS),
    });
    expect(cal.get("2026-08-23")).toMatchObject({ tipo: "FESTIVO", enDiaDeDescanso: true });
  });

  test("festivo en día que igual trabaja NO genera descanso compensatorio", () => {
    // L-V: miércoles 2026-04-01 festivo trabajado, pero es un día normal.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 8),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 1 }),
    });
    for (const [, dia] of cal) expect(dia.tipo).not.toBe("DESCANSO");
  });

  test("festivo trabajado en el día de descanso (N=1): el día siguiente es el compensatorio", () => {
    // Plaza martes-domingo, lunes 2026-04-06 festivo.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 6),
      hasta: new Date(2026, 3, 12),
      festivos: new Set(["2026-04-06"]),
      horarioPorDia: horarioPorDiaMaDo,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 1 }),
    });
    expect(cal.get("2026-04-06")).toMatchObject({ tipo: "FESTIVO", enDiaDeDescanso: true });
    expect(cal.get("2026-04-07")).toEqual({ tipo: "DESCANSO", horario: null, origen: "2026-04-06" });
    expect(cal.get("2026-04-08")?.tipo).toBe("NORMAL");
  });

  test("descanso compensatorio (N=2) cae dos días después", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 6),
      hasta: new Date(2026, 3, 12),
      festivos: new Set(["2026-04-06"]),
      horarioPorDia: horarioPorDiaMaDo,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 2 }),
    });
    expect(cal.get("2026-04-07")?.tipo).toBe("NORMAL");
    expect(cal.get("2026-04-08")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-06" });
  });

  test("si el día del compensatorio ya es descanso semanal, se corre al siguiente día normal", () => {
    // Plaza L-V, sábado 2026-04-04 festivo trabajado; +1 = domingo (LIBRE) -> lunes 04-06.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 8),
      festivos: new Set(["2026-04-04"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 1 }),
    });
    expect(cal.get("2026-04-05")?.tipo).toBe("LIBRE");
    expect(cal.get("2026-04-06")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-04" });
  });

  test("si el día del compensatorio es otro festivo trabajado, se corre al siguiente día normal", () => {
    // Martes-domingo: lunes 04-06 y martes 04-07 festivos. Solo el lunes es
    // día de descanso trabajado; su compensatorio no puede caer en el martes
    // (festivo trabajado) y pasa al miércoles.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 6),
      hasta: new Date(2026, 3, 12),
      festivos: new Set(["2026-04-06", "2026-04-07"]),
      horarioPorDia: horarioPorDiaMaDo,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 1 }),
    });
    expect(cal.get("2026-04-07")?.tipo).toBe("FESTIVO");
    expect(cal.get("2026-04-08")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-06" });
  });

  test("un festivo en día de descanso a fin de mes genera el compensatorio el día 1 del mes siguiente", () => {
    // Plaza L-V; domingo 2026-05-31 festivo. Se pide junio (desde=06-01).
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 5, 1),
      hasta: new Date(2026, 5, 5),
      festivos: new Set(["2026-05-31"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: true, diasDescansoCompensatorio: 1 }),
    });
    expect(cal.get("2026-06-01")).toMatchObject({ tipo: "DESCANSO", origen: "2026-05-31" });
  });

  test("con descansoCompensatorio=false, trabajar el festivo en día de descanso no genera nada", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 6),
      hasta: new Date(2026, 3, 12),
      festivos: new Set(["2026-04-06"]),
      horarioPorDia: horarioPorDiaMaDo,
      config: config({ ...CON_FESTIVOS, descansoCompensatorio: false }),
    });
    for (const [, dia] of cal) expect(dia.tipo).not.toBe("DESCANSO");
  });

  describe("plaza que trabaja de martes a domingo y descansa el lunes", () => {
    const configSalvavidas = config({
      ...CON_FESTIVOS,
      descansoCompensatorio: true,
      diasDescansoCompensatorio: 1,
    });

    test("sin festivos en el mes no hay ningún compensatorio (el lunes es su descanso normal)", () => {
      const cal = calcularCalendarioPlaza({
        desde: new Date(2026, 3, 1),
        hasta: new Date(2026, 3, 30),
        festivos: new Set(),
        horarioPorDia: horarioPorDiaMaDo,
        config: configSalvavidas,
      });
      for (const [, dia] of cal) expect(dia.tipo).not.toBe("DESCANSO");
      expect(cal.get("2026-04-06")?.tipo).toBe("LIBRE"); // lunes
      expect(cal.get("2026-04-07")?.tipo).toBe("NORMAL"); // martes
    });

    test("festivo entre semana (día que sí trabaja): lo trabaja y el lunes sigue siendo su descanso", () => {
      // Miércoles 2026-04-08 festivo.
      const cal = calcularCalendarioPlaza({
        desde: new Date(2026, 3, 6),
        hasta: new Date(2026, 3, 14),
        festivos: new Set(["2026-04-08"]),
        horarioPorDia: horarioPorDiaMaDo,
        config: configSalvavidas,
      });
      expect(cal.get("2026-04-08")?.tipo).toBe("FESTIVO");
      expect(cal.get("2026-04-09")?.tipo).toBe("NORMAL");
      expect(cal.get("2026-04-13")?.tipo).toBe("LIBRE");
      for (const [, dia] of cal) expect(dia.tipo).not.toBe("DESCANSO");
    });
  });
});
