import { DiaSemana, Frecuencia } from '@prisma/client';

import {
  buscarHuecoDiaConSplitEarliest,
  findNextValidDay,
} from '../../src/utils/schedulerUtils';
import {
  DefinicionTareaPreventivaService,
  pickDaysByFrecuencia,
} from '../../src/services/DefinicionTareaPreventivaService';

const HORA = (h: number, m = 0) => h * 60 + m;

function diasDelMes(anio: number, mes: number): Date[] {
  const total = new Date(anio, mes, 0).getDate();
  return Array.from({ length: total }, (_, i) => new Date(anio, mes - 1, i + 1));
}

describe('Scheduler de preventivas', () => {
  describe('buscarHuecoDiaConSplitEarliest', () => {
    // Jornada 8:00-16:00 con la mañana ocupada y almuerzo 13:00-14:00:
    // quedan libres exactamente 12:00-13:00 y 14:00-16:00 (60 + 120 = 180 min).
    const diaDelEnunciado = {
      startMin: HORA(8),
      endMin: HORA(16),
      ocupados: [{ i: HORA(8), f: HORA(12) }],
      bloqueos: [{ startMin: HORA(13), endMin: HORA(14) }],
    };

    // Libres de 30 + 60 + 60 min: ninguna pareja suma 150, solo los tres juntos.
    const diaMuyFragmentado = {
      startMin: HORA(8),
      endMin: HORA(17),
      ocupados: [
        { i: HORA(8, 30), f: HORA(10) },
        { i: HORA(11), f: HORA(15) },
        { i: HORA(16), f: HORA(17) },
      ],
      bloqueos: [],
    };

    test('PU-S1 - parte una tarea de 3h en 12:00-13:00 y 14:00-16:00 en vez de excluirla', () => {
      const plan = buscarHuecoDiaConSplitEarliest({
        ...diaDelEnunciado,
        durMin: 180,
        maxBloques: 3,
      });

      expect(plan).toEqual([
        { i: HORA(12), f: HORA(13) },
        { i: HORA(14), f: HORA(16) },
      ]);
    });

    test('PU-S2 - con maxBloques 3 aprovecha tres huecos sueltos', () => {
      const plan = buscarHuecoDiaConSplitEarliest({
        ...diaMuyFragmentado,
        durMin: 150,
        maxBloques: 3,
      });

      expect(plan).toEqual([
        { i: HORA(8), f: HORA(8, 30) },
        { i: HORA(10), f: HORA(11) },
        { i: HORA(15), f: HORA(16) },
      ]);
    });

    test('PU-S3 - con maxBloques 2 el comportamiento previo no cambia', () => {
      // El caso de 2 bloques sigue resolviendose igual que antes del cambio.
      expect(
        buscarHuecoDiaConSplitEarliest({
          ...diaDelEnunciado,
          durMin: 180,
          maxBloques: 2,
        }),
      ).toEqual([
        { i: HORA(12), f: HORA(13) },
        { i: HORA(14), f: HORA(16) },
      ]);

      // Y lo que antes no tenia solucion sigue sin tenerla con maxBloques 2.
      expect(
        buscarHuecoDiaConSplitEarliest({
          ...diaMuyFragmentado,
          durMin: 150,
          maxBloques: 2,
        }),
      ).toBeNull();
    });

    test('PU-S4 - un solo bloque sigue teniendo prioridad sobre la division', () => {
      const plan = buscarHuecoDiaConSplitEarliest({
        startMin: HORA(8),
        endMin: HORA(17),
        durMin: 180,
        ocupados: [{ i: HORA(8), f: HORA(12) }],
        bloqueos: [{ startMin: HORA(13), endMin: HORA(14) }],
        maxBloques: 3,
      });

      expect(plan).toEqual([{ i: HORA(14), f: HORA(17) }]);
    });
  });

  describe('pickDaysByFrecuencia', () => {
    // Marzo 2026: los martes caen 3, 10, 17, 24 y 31.
    const marzo = diasDelMes(2026, 3);

    test('PU-S4 - QUINCENAL usa el dia de semana y toma la 1a y la 3a ocurrencia', () => {
      const dias = pickDaysByFrecuencia(marzo, {
        frecuencia: Frecuencia.QUINCENAL,
        diaSemanaProgramado: DiaSemana.MARTES,
      });

      expect(dias.map((d) => d.getDate())).toEqual([3, 17]);
      // 14 dias exactos de separacion
      expect(dias[1].getTime() - dias[0].getTime()).toBe(14 * 24 * 60 * 60 * 1000);
    });

    test('PU-S5 - SEMANAL sigue devolviendo todas las ocurrencias del dia elegido', () => {
      const dias = pickDaysByFrecuencia(marzo, {
        frecuencia: Frecuencia.SEMANAL,
        diaSemanaProgramado: DiaSemana.MARTES,
      });

      expect(dias.map((d) => d.getDate())).toEqual([3, 10, 17, 24, 31]);
    });

    test('PU-S6 - QUINCENAL sin dia de semana cae al calculo por fecha ancla', () => {
      const dias = pickDaysByFrecuencia(marzo, {
        frecuencia: Frecuencia.QUINCENAL,
        diaSemanaProgramado: null,
        creadoEn: new Date(2026, 2, 2),
      });

      expect(dias.map((d) => d.getDate())).toEqual([2, 16, 30]);
    });
  });

  describe('reglas de festivos por prioridad', () => {
    const horarios = new Map(
      [
        DiaSemana.LUNES,
        DiaSemana.MARTES,
        DiaSemana.MIERCOLES,
        DiaSemana.JUEVES,
        DiaSemana.VIERNES,
      ].map((dia) => [dia, { startMin: HORA(8), endMin: HORA(16) }]),
    );
    const festivos = new Set(['2026-03-02']);

    test('PU-S7 - P1 que cae en festivo pasa al siguiente dia habil', () => {
      const fecha = findNextValidDay({
        start: new Date(2026, 2, 2),
        periodoAnio: 2026,
        periodoMes: 3,
        prioridad: 1,
        horariosPorDia: horarios,
        festivosSet: festivos,
      });

      expect(fecha).not.toBeNull();
      expect(fecha?.getDate()).toBe(3);
    });

    test.each([2, 3])(
      'PU-S8 - P%s que cae en festivo se omite para enviarla a excluidas',
      (prioridad) => {
        expect(
          findNextValidDay({
            start: new Date(2026, 2, 2),
            periodoAnio: 2026,
            periodoMes: 3,
            prioridad,
            horariosPorDia: horarios,
            festivosSet: festivos,
          }),
        ).toBeNull();
      },
    );
  });

  describe('validarProgramacionFrecuencia', () => {
    const service: any = new DefinicionTareaPreventivaService({} as any);

    test('PU-S9 - QUINCENAL exige dia de la semana', () => {
      expect(() =>
        service.validarProgramacionFrecuencia({
          frecuencia: Frecuencia.QUINCENAL,
          diaSemanaProgramado: null,
        }),
      ).toThrow(/quincenales deben tener un día de la semana/i);

      expect(() =>
        service.validarProgramacionFrecuencia({
          frecuencia: Frecuencia.QUINCENAL,
          diaSemanaProgramado: DiaSemana.MARTES,
        }),
      ).not.toThrow();
    });

    test('PU-S10 - SEMANAL sigue exigiendo dia programado', () => {
      expect(() =>
        service.validarProgramacionFrecuencia({
          frecuencia: Frecuencia.SEMANAL,
          diaSemanaProgramado: null,
        }),
      ).toThrow(/semanales deben tener un día programado/i);
    });
  });
});
