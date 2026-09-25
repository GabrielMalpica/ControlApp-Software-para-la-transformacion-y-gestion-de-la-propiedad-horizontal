import { DiaSemana } from "@prisma/client";
import {
  calcularCalendarioPlaza,
  CONFIG_FESTIVO_DEFAULT,
  type ConfigFestivoNecesidad,
} from "../../src/utils/calendarioPlazaCore";
import type { HorarioDia } from "../../src/utils/agenda";

const HORARIO_LV: HorarioDia = { startMin: 7 * 60, endMin: 16 * 60 };

// L-V 07-16, sin fin de semana.
const DIAS_LV: DiaSemana[] = [
  DiaSemana.LUNES,
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
];

function horarioPorDiaLV(dia: DiaSemana): HorarioDia | null {
  return DIAS_LV.includes(dia) ? HORARIO_LV : null;
}

function config(overrides: Partial<ConfigFestivoNecesidad> = {}): ConfigFestivoNecesidad {
  return { ...CONFIG_FESTIVO_DEFAULT, ...overrides };
}

describe("calcularCalendarioPlaza", () => {
  test("festivo sin trabajaFestivos queda LIBRE (día no laborable para la plaza)", () => {
    // 2026-04-01 es miércoles.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 1),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config(),
    });
    expect(cal.get("2026-04-01")).toEqual({ tipo: "FESTIVO", horario: null });
  });

  test("festivo con trabajaFestivos usa el horario festivo propio", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 1),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
      }),
    });
    expect(cal.get("2026-04-01")).toEqual({
      tipo: "FESTIVO",
      horario: { startMin: 9 * 60, endMin: 15 * 60, descansoStartMin: undefined, descansoEndMin: undefined },
    });
  });

  test("festivo que cae en domingo se resuelve como FESTIVO (precedencia sobre domingo)", () => {
    // 2026-08-23 es domingo.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(["2026-08-23"]),
      horarioPorDia: (dia) => (dia === DiaSemana.DOMINGO ? { startMin: 480, endMin: 600 } : null),
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "07:00",
        festivoHoraCierre: "12:00",
      }),
    });
    const dia = cal.get("2026-08-23")!;
    expect(dia.tipo).toBe("FESTIVO");
    expect(dia.horario).toEqual({ startMin: 7 * 60, endMin: 12 * 60, descansoStartMin: undefined, descansoEndMin: undefined });
  });

  test("domingo trabajado (con horario) queda marcado DOMINGO", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(),
      horarioPorDia: (dia) => (dia === DiaSemana.DOMINGO ? { startMin: 480, endMin: 600 } : null),
      config: config(),
    });
    expect(cal.get("2026-08-23")).toEqual({
      tipo: "DOMINGO",
      horario: { startMin: 480, endMin: 600 },
    });
  });

  test("domingo sin horario configurado queda LIBRE", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 23),
      festivos: new Set(),
      horarioPorDia: horarioPorDiaLV,
      config: config(),
    });
    expect(cal.get("2026-08-23")).toEqual({ tipo: "LIBRE", horario: null });
  });

  test("descanso compensatorio (N=1) tras un festivo trabajado cae al día siguiente", () => {
    // Miércoles 2026-04-01 festivo trabajado -> descanso jueves 2026-04-02.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 5),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 1,
      }),
    });
    expect(cal.get("2026-04-01")?.tipo).toBe("FESTIVO");
    expect(cal.get("2026-04-02")).toEqual({
      tipo: "DESCANSO",
      horario: null,
      origen: "2026-04-01",
    });
    // El resto de la semana sigue normal.
    expect(cal.get("2026-04-03")?.tipo).toBe("NORMAL");
  });

  test("descanso compensatorio (N=2) cae dos días después", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 5),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 2,
      }),
    });
    expect(cal.get("2026-04-02")?.tipo).toBe("NORMAL");
    expect(cal.get("2026-04-03")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-01" });
  });

  test("descanso que caería en un día que la plaza no trabaja se corre al siguiente día laborable", () => {
    // Viernes 2026-04-03 es festivo trabajado; +1 día cae sábado (LIBRE, la
    // plaza no trabaja sábado) -> se corre al lunes 2026-04-06 (siguiente NORMAL).
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 8),
      festivos: new Set(["2026-04-03"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 1,
      }),
    });
    expect(cal.get("2026-04-04")?.tipo).toBe("LIBRE"); // sábado, sin cambios
    expect(cal.get("2026-04-05")?.tipo).toBe("LIBRE"); // domingo, sin horario
    expect(cal.get("2026-04-06")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-03" });
  });

  test("descanso que caería en otro festivo (que la plaza sí trabaja) también se corre", () => {
    // 2026-04-01 (miércoles) y 2026-04-02 (jueves) festivos consecutivos,
    // ambos trabajados. El descanso de 04-01 no puede caer en 04-02 (festivo
    // trabajado): se corre al siguiente NORMAL (2026-04-03, viernes).
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 5),
      festivos: new Set(["2026-04-01", "2026-04-02"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 1,
      }),
    });
    expect(cal.get("2026-04-02")?.tipo).toBe("FESTIVO");
    expect(cal.get("2026-04-03")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-01" });
    // El descanso que origina el 04-02 cae, a su vez, el 04-04 (sábado=LIBRE) -> se corre al 04-06.
  });

  test("un festivo a fin de mes genera el descanso el día 1 del mes siguiente", () => {
    // 2026-04-30 es jueves; se pide el calendario de mayo (desde=05-01), y el
    // margen de arrastre interno debe alcanzar a ver el festivo de abril.
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 4, 1),
      hasta: new Date(2026, 4, 5),
      festivos: new Set(["2026-04-30"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 1,
      }),
    });
    expect(cal.get("2026-05-01")).toMatchObject({ tipo: "DESCANSO", origen: "2026-04-30" });
  });

  test("con descansoCompensatorio=false, un festivo/domingo trabajado no genera ningún descanso", () => {
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 3, 1),
      hasta: new Date(2026, 3, 5),
      festivos: new Set(["2026-04-01"]),
      horarioPorDia: horarioPorDiaLV,
      config: config({
        trabajaFestivos: true,
        festivoHoraApertura: "09:00",
        festivoHoraCierre: "15:00",
        descansoCompensatorio: false,
      }),
    });
    expect(cal.get("2026-04-02")?.tipo).toBe("NORMAL");
    for (const [, dia] of cal) {
      expect(dia.tipo).not.toBe("DESCANSO");
    }
  });

  test("un domingo trabajado también genera descanso compensatorio si está activo", () => {
    // 2026-08-23 domingo trabajado 08-16; +1 día = lunes 2026-08-24 (NORMAL, L-V).
    const cal = calcularCalendarioPlaza({
      desde: new Date(2026, 7, 23),
      hasta: new Date(2026, 7, 25),
      festivos: new Set(),
      horarioPorDia: (dia) =>
        dia === DiaSemana.DOMINGO ? { startMin: 480, endMin: 960 } : horarioPorDiaLV(dia),
      config: config({
        descansoCompensatorio: true,
        diasDescansoCompensatorio: 1,
      }),
    });
    expect(cal.get("2026-08-23")?.tipo).toBe("DOMINGO");
    expect(cal.get("2026-08-24")).toMatchObject({ tipo: "DESCANSO", origen: "2026-08-23" });
  });
});
