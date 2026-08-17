jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return {
    ...real,
    isFestivoDate: jest.fn().mockResolvedValue(false),
  };
});

jest.mock('../../src/utils/operarioAvailability', () => {
  const real = jest.requireActual('../../src/utils/operarioAvailability');
  return {
    ...real,
    validarIntervaloProgramacion: jest.fn().mockResolvedValue({ ok: true }),
    validarOperariosDisponiblesEnFecha: jest
      .fn()
      .mockResolvedValue({ ok: true, noDisponibles: [] }),
  };
});

import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

describe('reordenamiento coordinado del borrador', () => {
  test('incluye y ajusta la tarea del segundo operario conectada por una tarea compartida', async () => {
    const fecha = new Date(2026, 2, 4);
    const tareas: any[] = [
      {
        id: 1,
        descripcion: 'Tarea operario uno',
        fechaInicio: new Date(2026, 2, 4, 8),
        fechaFin: new Date(2026, 2, 4, 9),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        operarios: [{ id: 'op-1', usuario: { nombre: 'Ana' } }],
      },
      {
        id: 2,
        descripcion: 'Tarea compartida',
        fechaInicio: new Date(2026, 2, 4, 9),
        fechaFin: new Date(2026, 2, 4, 10),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        operarios: [
          { id: 'op-1', usuario: { nombre: 'Ana' } },
          { id: 'op-2', usuario: { nombre: 'Luis' } },
        ],
      },
      {
        id: 3,
        descripcion: 'Tarea operario dos',
        fechaInicio: new Date(2026, 2, 4, 10),
        fechaFin: new Date(2026, 2, 4, 11),
        duracionMinutos: 60,
        ocurrenciaPlanId: null,
        operarios: [{ id: 'op-2', usuario: { nombre: 'Luis' } }],
      },
    ];
    const prisma: any = {
      tarea: {
        findMany: jest.fn().mockResolvedValue(tareas),
        findFirst: jest.fn().mockResolvedValue(null),
        update: jest.fn(async ({ where, data }: any) => {
          const tarea = tareas.find((item) => item.id === where.id);
          Object.assign(tarea, data);
          return tarea;
        }),
      },
      conjuntoHorario: {
        findFirst: jest.fn().mockResolvedValue({
          horaApertura: '08:00',
          horaCierre: '17:00',
          descansoInicio: '12:00',
          descansoFin: '13:00',
        }),
      },
      $transaction: jest.fn(async (callback: any) => callback(prisma)),
    };
    const service = new DefinicionTareaPreventivaService(prisma);

    const resultado = await service.reordenarTareasBorradorDia({
      conjuntoId: '9001',
      fecha,
      tareaIds: [2, 1],
    });

    expect(resultado).toMatchObject({
      ok: true,
      reordenadas: 3,
      ajustadasPorDependencia: 1,
      operariosInvolucrados: ['Ana', 'Luis'],
    });
    expect(tareas.find((tarea) => tarea.id === 2)?.fechaInicio.getHours()).toBe(8);
    expect(tareas.find((tarea) => tarea.id === 1)?.fechaInicio.getHours()).toBe(9);
    expect(tareas.find((tarea) => tarea.id === 3)?.fechaInicio.getHours()).toBe(10);
  });
});
