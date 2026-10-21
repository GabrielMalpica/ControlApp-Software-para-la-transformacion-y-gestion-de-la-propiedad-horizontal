import { DiaProgramado, DiaSemana, Frecuencia } from "@prisma/client";
import { pickDaysByFrecuencia } from "../../src/services/DefinicionTareaPreventivaService";

describe("pickDaysByFrecuencia: días seleccionados y festivos", () => {
  const dias = [
    new Date(2026, 10, 1),
    new Date(2026, 10, 2),
    new Date(2026, 10, 3),
    new Date(2026, 10, 4),
  ];

  test("DIARIA sin selección conserva todas las fechas candidatas", () => {
    expect(pickDaysByFrecuencia(dias, { frecuencia: Frecuencia.DIARIA })).toEqual(dias);
  });

  test("DIARIA seleccionada filtra por día de semana real", () => {
    expect(
      pickDaysByFrecuencia(dias, {
        frecuencia: Frecuencia.DIARIA,
        diasSemanaProgramados: [DiaSemana.LUNES, DiaSemana.MIERCOLES],
      }),
    ).toEqual([dias[1], dias[3]]);
  });

  test("SEMANAL FESTIVO selecciona solo festivos, independiente del día semanal real", () => {
    const festivos = new Set(["2026-11-02", "2026-11-04"]);
    expect(
      pickDaysByFrecuencia(
        dias,
        {
          frecuencia: Frecuencia.SEMANAL,
          diaSemanaProgramado: DiaProgramado.FESTIVO,
        },
        festivos,
      ),
    ).toEqual([dias[1], dias[3]]);
  });
});
