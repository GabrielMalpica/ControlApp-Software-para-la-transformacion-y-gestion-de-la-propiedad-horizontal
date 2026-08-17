import { DiaSemana } from "@prisma/client";
import {
  allowedIntervalsForUserWithAvailability,
  validarIntervaloProgramacion,
} from "../../src/utils/operarioAvailability";

describe("Disponibilidad canónica del cronograma", () => {
  test("acepta un bloque que termina exactamente al cierre y rechaza cualquier exceso", async () => {
    const prisma: any = {
      conjuntoHorario: {
        findUnique: jest.fn().mockResolvedValue({
          horaApertura: "07:00",
          horaCierre: "11:00",
          descansoInicio: null,
          descansoFin: null,
        }),
      },
    };
    const sabado = new Date(2026, 7, 22, 10, 0, 0, 0);

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "SERRAMONTE",
        fechaInicio: sabado,
        fechaFin: new Date(2026, 7, 22, 11, 0, 0, 0),
        operariosIds: [],
      }),
    ).resolves.toMatchObject({ ok: true });

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "SERRAMONTE",
        fechaInicio: new Date(2026, 7, 22, 10, 30, 0, 0),
        fechaFin: new Date(2026, 7, 22, 11, 30, 0, 0),
        operariosIds: [],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "FUERA_HORARIO_CONJUNTO" });

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "SERRAMONTE",
        fechaInicio: new Date(2026, 7, 22, 11, 0, 0, 0),
        fechaFin: new Date(2026, 7, 22, 12, 0, 0, 0),
        operariosIds: [],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "FUERA_HORARIO_CONJUNTO" });
  });

  test("media jornada valida el intervalo completo y sábado conserva el horario reducido", () => {
    const horario = {
      startMin: 8 * 60,
      endMin: 16 * 60,
      descansoStartMin: 12 * 60,
      descansoEndMin: 13 * 60,
    };
    expect(
      allowedIntervalsForUserWithAvailability({
        dia: DiaSemana.LUNES,
        horario,
        jornadaLaboral: "MEDIO_TIEMPO",
        patronJornada: "MEDIO_SEMANA_SABADO",
      }),
    ).toEqual([{ i: 8 * 60, f: 12 * 60 }]);
    expect(
      allowedIntervalsForUserWithAvailability({
        dia: DiaSemana.SABADO,
        horario: { startMin: 7 * 60, endMin: 11 * 60 },
        jornadaLaboral: "MEDIO_TIEMPO",
        patronJornada: "MEDIO_SEMANA_SABADO",
      }),
    ).toEqual([{ i: 7 * 60, f: 11 * 60 }]);
  });

  test("la intersección rechaza un bloque válido para el conjunto pero fuera de la media jornada", async () => {
    const prisma: any = {
      conjuntoHorario: {
        findUnique: jest.fn().mockResolvedValue({
          horaApertura: "08:00",
          horaCierre: "16:00",
          descansoInicio: "12:00",
          descansoFin: "13:00",
        }),
      },
      operario: {
        findMany: jest.fn().mockResolvedValue([
          {
            id: "op-medio",
            usuario: {
              jornadaLaboral: "MEDIO_TIEMPO",
              patronJornada: "MEDIO_SEMANA_SABADO",
            },
          },
        ]),
      },
      operarioDisponibilidadPeriodo: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 15, 0),
        fechaFin: new Date(2026, 7, 17, 16, 0),
        operariosIds: ["op-medio"],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "FUERA_HORARIO_OPERARIO" });
  });

  test("fines de semana no habilita días laborales", () => {
    const horario = { startMin: 8 * 60, endMin: 16 * 60 };
    expect(
      allowedIntervalsForUserWithAvailability({
        dia: DiaSemana.MARTES,
        horario,
        jornadaLaboral: "FINES_DE_SEMANA",
        patronJornada: null,
      }),
    ).toEqual([]);
    expect(
      allowedIntervalsForUserWithAvailability({
        dia: DiaSemana.SABADO,
        horario,
        jornadaLaboral: "FINES_DE_SEMANA",
        patronJornada: null,
      }),
    ).toEqual([{ i: 8 * 60, f: 16 * 60 }]);
    expect(
      allowedIntervalsForUserWithAvailability({
        dia: DiaSemana.DOMINGO,
        horario,
        jornadaLaboral: "FINES_DE_SEMANA",
        patronJornada: null,
        disponibilidad: {
          trabajaDomingo: true,
          diaDescanso: DiaSemana.LUNES,
        },
      }),
    ).toEqual([{ i: 8 * 60, f: 16 * 60 }]);
  });
});
