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

describe("Necesidades operativas: horario propio de una plaza (ConjuntoNecesidadOperario)", () => {
  test("una plaza con horario especial puede exceder el cierre del conjunto", async () => {
    const prisma: any = {
      conjuntoHorario: {
        findUnique: jest.fn().mockResolvedValue({
          horaApertura: "07:00",
          horaCierre: "17:00",
          descansoInicio: null,
          descansoFin: null,
        }),
      },
      conjuntoNecesidadOperario: {
        // Todero #2: 10:00-19:00, mientras el conjunto cierra a las 17:00.
        findMany: jest.fn().mockResolvedValue([
          {
            operarioId: "todero-2",
            horarioEspecial: true,
            horarios: [
              { horaApertura: "10:00", horaCierre: "19:00", descansoInicio: null, descansoFin: null },
            ],
          },
        ]),
      },
      operario: {
        findMany: jest.fn().mockResolvedValue([
          { id: "todero-2", usuario: { jornadaLaboral: null, patronJornada: null } },
        ]),
      },
      operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    };

    // Lunes 17 de agosto de 2026.
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 16, 0),
        fechaFin: new Date(2026, 7, 17, 17, 0),
        operariosIds: ["todero-2"],
      }),
    ).resolves.toMatchObject({ ok: true });

    // Más allá del cierre del conjunto pero dentro del horario de la plaza.
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 18, 0),
        fechaFin: new Date(2026, 7, 17, 19, 0),
        operariosIds: ["todero-2"],
      }),
    ).resolves.toMatchObject({ ok: true });

    // Fuera incluso del horario extendido de la plaza.
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 19, 0),
        fechaFin: new Date(2026, 7, 17, 20, 0),
        operariosIds: ["todero-2"],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "FUERA_HORARIO_CONJUNTO" });
  });

  test("una plaza con horario especial puede operar un día en que el conjunto no tiene horario (salvavidas solo domingo)", async () => {
    const prisma: any = {
      conjuntoHorario: {
        // El conjunto no tiene fila configurada para el domingo.
        findUnique: jest.fn().mockResolvedValue(null),
      },
      conjuntoNecesidadOperario: {
        findMany: jest.fn().mockResolvedValue([
          {
            operarioId: "salvavidas-1",
            horarioEspecial: true,
            horarios: [
              { horaApertura: "08:00", horaCierre: "17:00", descansoInicio: null, descansoFin: null },
            ],
          },
        ]),
      },
      operario: {
        findMany: jest.fn().mockResolvedValue([
          { id: "salvavidas-1", usuario: { jornadaLaboral: null, patronJornada: null } },
        ]),
      },
      // El horario de la plaza no anula la autorización legal de trabajar
      // domingo: son capas independientes. Un salvavidas de plaza dominical
      // necesita trabajaDomingo=true en su periodo de disponibilidad.
      operarioDisponibilidadPeriodo: {
        findFirst: jest.fn().mockResolvedValue({
          trabajaDomingo: true,
          diaDescanso: DiaSemana.LUNES,
        }),
      },
    };

    // Domingo 23 de agosto de 2026.
    const domingo = new Date(2026, 7, 23, 10, 0, 0, 0);
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: domingo,
        fechaFin: new Date(2026, 7, 23, 11, 0, 0, 0),
        operariosIds: ["salvavidas-1"],
      }),
    ).resolves.toMatchObject({ ok: true });

    // Sin operarios (solo el conjunto), el domingo sigue sin horario: el
    // horario de la plaza no se filtra a ciegas cuando nadie lo pide.
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: domingo,
        fechaFin: new Date(2026, 7, 23, 11, 0, 0, 0),
        operariosIds: [],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "SIN_HORARIO_CONJUNTO" });
  });

  test("una plaza sin horario especial hereda el horario general del conjunto (comportamiento actual intacto)", async () => {
    const prisma: any = {
      conjuntoHorario: {
        findUnique: jest.fn().mockResolvedValue({
          horaApertura: "07:00",
          horaCierre: "16:00",
          descansoInicio: null,
          descansoFin: null,
        }),
      },
      conjuntoNecesidadOperario: {
        findMany: jest.fn().mockResolvedValue([
          { operarioId: "todero-1", horarioEspecial: false, horarios: [] },
        ]),
      },
      operario: {
        findMany: jest.fn().mockResolvedValue([
          { id: "todero-1", usuario: { jornadaLaboral: null, patronJornada: null } },
        ]),
      },
      operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    };

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 15, 0),
        fechaFin: new Date(2026, 7, 17, 16, 0),
        operariosIds: ["todero-1"],
      }),
    ).resolves.toMatchObject({ ok: true });

    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: new Date(2026, 7, 17, 16, 0),
        fechaFin: new Date(2026, 7, 17, 17, 0),
        operariosIds: ["todero-1"],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "FUERA_HORARIO_CONJUNTO" });
  });

  test("una plaza con horario especial que no configuró un día no trabaja ese día, aunque el conjunto sí opere", async () => {
    const prisma: any = {
      conjuntoHorario: {
        findUnique: jest.fn().mockResolvedValue({
          horaApertura: "07:00",
          horaCierre: "16:00",
          descansoInicio: null,
          descansoFin: null,
        }),
      },
      conjuntoNecesidadOperario: {
        // Piscinero lunes/miércoles/viernes: sin fila para el martes.
        findMany: jest.fn().mockResolvedValue([
          { operarioId: "piscinero-1", horarioEspecial: true, horarios: [] },
        ]),
      },
      operario: {
        findMany: jest.fn().mockResolvedValue([
          { id: "piscinero-1", usuario: { jornadaLaboral: null, patronJornada: null } },
        ]),
      },
      operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    };

    // Martes 18 de agosto de 2026.
    const martes = new Date(2026, 7, 18, 9, 0, 0, 0);
    await expect(
      validarIntervaloProgramacion({
        prisma,
        conjuntoId: "C-1",
        fechaInicio: martes,
        fechaFin: new Date(2026, 7, 18, 10, 0, 0, 0),
        operariosIds: ["piscinero-1"],
      }),
    ).resolves.toMatchObject({ ok: false, motivo: "SIN_HORARIO_CONJUNTO" });
  });
});
