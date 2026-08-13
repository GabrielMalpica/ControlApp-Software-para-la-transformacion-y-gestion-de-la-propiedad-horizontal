import { DiaSemana, Frecuencia } from '@prisma/client';

jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return {
    ...real,
    getFestivosSet: jest.fn().mockResolvedValue(new Set<string>()),
    isFestivoDate: jest.fn().mockResolvedValue(false),
  };
});

import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

const CONJUNTO = '9001';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

const DIAS_LABORALES = [
  DiaSemana.LUNES,
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
];

function definicion(overrides: Record<string, any> = {}) {
  return {
    id: 77,
    conjuntoId: CONJUNTO,
    descripcion: 'Lavado de fachada',
    frecuencia: Frecuencia.MENSUAL,
    diaSemanaProgramado: null,
    diaMesProgramado: 2,
    prioridad: 2,
    duracionMinutosFija: 120,
    diasParaCompletar: 1,
    ubicacionId: 1,
    elementoId: 2,
    supervisorId: null,
    insumosPlanJson: null,
    maquinariaPlanJson: null,
    herramientasPlanJson: null,
    creadoEn: new Date(2026, 0, 1),
    operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
    supervisor: null,
    ...overrides,
  };
}

function construirPrisma(opts: {
  definiciones: any[];
  tareasEnBorrador?: any[];
}) {
  const tareasCreadas: any[] = [];
  let secuencia = 1000;

  const prisma: any = {
    tareasCreadas,
    definicionTareaPreventiva: {
      findMany: jest.fn().mockResolvedValue(opts.definiciones),
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn().mockResolvedValue(null),
    },
    conjuntoHorario: {
      findMany: jest.fn().mockResolvedValue(
        DIAS_LABORALES.map((dia) => ({
          dia,
          horaApertura: '08:00',
          horaCierre: '16:00',
          descansoInicio: null,
          descansoFin: null,
        })),
      ),
      findFirst: jest.fn().mockResolvedValue({
        horaApertura: '08:00',
        horaCierre: '16:00',
        descansoInicio: null,
        descansoFin: null,
      }),
    },
    tarea: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      count: jest.fn().mockResolvedValue(0),
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn(async ({ where }: any) => {
        // Consulta de "definiciones ya en borrador".
        if (where?.borrador === true && where?.tipo === 'PREVENTIVA' && !where.fechaFin) {
          return opts.tareasEnBorrador ?? [];
        }
        return tareasCreadas;
      }),
      create: jest.fn(async ({ data }: any) => {
        const creada = { ...data, id: ++secuencia };
        tareasCreadas.push(creada);
        return creada;
      }),
    },
    preventivaExcluidaBorrador: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      findMany: jest.fn().mockResolvedValue([]),
      count: jest.fn().mockResolvedValue(0),
      create: jest.fn(async ({ data }: any) => ({ ...data, id: ++secuencia })),
    },
    preventivaBorradorEvento: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      findFirst: jest.fn().mockResolvedValue(null),
      create: jest.fn().mockResolvedValue({}),
    },
    operario: {
      findMany: jest.fn().mockResolvedValue([
        { id: 'op-1', usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null } },
      ]),
      findUnique: jest.fn().mockResolvedValue({
        usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
        empresa: { limiteHorasSemana: 48 },
      }),
    },
    operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    conjunto: {
      findUnique: jest.fn().mockResolvedValue({
        limiteHorasSemanaOverride: null,
        empresa: { limiteHorasSemana: 48 },
      }),
    },
    auditoriaEvento: {
      create: jest.fn().mockResolvedValue({}),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    $queryRaw: jest.fn().mockResolvedValue([]),
    $transaction: jest.fn(),
  };

  prisma.$transaction.mockImplementation(async (cb: any) => cb(prisma));

  return prisma;
}

describe('Borrador persistente', () => {
  test('PU-B1 - modo RESET (default) sigue descartando el borrador previo', async () => {
    const prisma = construirPrisma({ definiciones: [definicion()] });
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(prisma.tarea.deleteMany).toHaveBeenCalled();
    expect(prisma.preventivaExcluidaBorrador.deleteMany).toHaveBeenCalled();
    expect(prisma.preventivaBorradorEvento.deleteMany).toHaveBeenCalled();
  });

  test('PU-B2 - modo CONSERVAR no borra nada del periodo', async () => {
    const prisma = construirPrisma({ definiciones: [definicion()] });
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
      modo: 'CONSERVAR',
    });

    expect(prisma.tarea.deleteMany).not.toHaveBeenCalled();
    expect(prisma.preventivaBorradorEvento.deleteMany).not.toHaveBeenCalled();

    // La unica limpieza permitida es la de periodos ANTERIORES, que corre siempre.
    const borradosExcluidas =
      prisma.preventivaExcluidaBorrador.deleteMany.mock.calls;
    for (const [args] of borradosExcluidas) {
      expect(args.where.periodoMes).toBeUndefined();
      expect(args.where.OR).toBeDefined();
    }
  });

  test('PU-B3 - CONSERVAR salta las definiciones que ya están en el borrador', async () => {
    const prisma = construirPrisma({
      definiciones: [definicion({ id: 77 })],
      tareasEnBorrador: [
        {
          definicionId: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
      ],
    });

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
      modo: 'CONSERVAR',
    });

    expect(creadas).toBe(0);
    expect(prisma.tarea.create).not.toHaveBeenCalled();
  });

  test('PU-B4 - CONSERVAR sí planifica una preventiva nueva', async () => {
    const prisma = construirPrisma({
      definiciones: [definicion({ id: 77 }), definicion({ id: 88, descripcion: 'Poda de setos' })],
      // Solo la 77 estaba planificada.
      tareasEnBorrador: [
        {
          definicionId: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
      ],
    });

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
      modo: 'CONSERVAR',
    });

    expect(creadas).toBe(1);
    expect(prisma.tareasCreadas[0].definicionId).toBe(88);
  });

  test('PU-B5 - la clave de respaldo cubre tareas antiguas sin definicionId', async () => {
    const prisma = construirPrisma({
      definiciones: [definicion({ id: 77 })],
      tareasEnBorrador: [
        {
          definicionId: null,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
      ],
    });

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
      modo: 'CONSERVAR',
    });

    expect(creadas).toBe(0);
  });

  describe('estadoBorrador', () => {
    test('PU-B6 - informa de las preventivas que faltan por planificar', async () => {
      const prisma = construirPrisma({ definiciones: [] });
      prisma.tarea.count.mockResolvedValue(12);
      prisma.preventivaExcluidaBorrador.count.mockResolvedValue(2);
      prisma.preventivaBorradorEvento.findFirst.mockResolvedValue({
        creadoEn: new Date(2026, 1, 28),
        metadataJson: {
          versionesDefiniciones: [
            { id: 77, actualizadoEn: new Date(0).toISOString() },
          ],
        },
      });
      prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
        {
          id: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
        {
          id: 88,
          descripcion: 'Poda de setos',
          ubicacionId: 1,
          elementoId: 3,
          frecuencia: Frecuencia.SEMANAL,
        },
      ]);
      prisma.tarea.findMany.mockResolvedValue([
        {
          definicionId: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
      ]);

      const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
      const out = await service.estadoBorrador({
        conjuntoId: CONJUNTO,
        anio: 2026,
        mes: 3,
      });

      expect(out.existe).toBe(true);
      expect(out.totalTareas).toBe(12);
      expect(out.excluidasPendientes).toBe(2);
      expect(out.definicionesSinPlanificar).toBe(1);
      expect(out.descripcionesSinPlanificar).toEqual(['Poda de setos']);
      expect(out.definicionesModificadas).toBe(0);
      expect(out.desactualizado).toBe(true);
    });

    test('PU-B7 - sin tareas ni excluidas, el borrador no existe', async () => {
      const prisma = construirPrisma({ definiciones: [] });
      const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

      const out = await service.estadoBorrador({
        conjuntoId: CONJUNTO,
        anio: 2026,
        mes: 3,
      });

      expect(out.existe).toBe(false);
    });

    test('PU-B8 - filas antiguas sin marca no se ofrecen como cache guardado', async () => {
      const prisma = construirPrisma({ definiciones: [] });
      prisma.tarea.count.mockResolvedValue(4);
      const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

      const out = await service.estadoBorrador({
        conjuntoId: CONJUNTO,
        anio: 2026,
        mes: 3,
      });

      expect(out.existe).toBe(false);
      expect(out.borradorAnteriorSinMarca).toBe(true);
      expect(out.cacheGestionado).toBe(false);
    });

    test('PU-B9 - detecta una definicion modificada despues de generar', async () => {
      const prisma = construirPrisma({ definiciones: [] });
      prisma.tarea.count.mockResolvedValue(1);
      prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
        {
          id: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
          creadoEn: new Date('2026-02-01T10:00:00Z'),
          actualizadoEn: new Date('2026-03-02T10:00:00Z'),
        },
      ]);
      prisma.tarea.findMany.mockResolvedValue([
        {
          definicionId: 77,
          descripcion: 'Lavado de fachada',
          ubicacionId: 1,
          elementoId: 2,
          frecuencia: Frecuencia.MENSUAL,
        },
      ]);
      prisma.preventivaBorradorEvento.findFirst.mockResolvedValue({
        creadoEn: new Date('2026-03-01T10:00:00Z'),
        metadataJson: {
          versionesDefiniciones: [
            { id: 77, actualizadoEn: '2026-02-01T10:00:00.000Z' },
          ],
        },
      });
      const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

      const out = await service.estadoBorrador({
        conjuntoId: CONJUNTO,
        anio: 2026,
        mes: 3,
      });

      expect(out.existe).toBe(true);
      expect(out.desactualizado).toBe(true);
      expect(out.definicionesModificadas).toBe(1);
      expect(out.descripcionesModificadas).toEqual(['Lavado de fachada']);
    });
  });

  test('PU-B10 - descartarBorradorMes borra las tres tablas y audita', async () => {
    const prisma = construirPrisma({ definiciones: [] });
    prisma.tarea.deleteMany.mockResolvedValue({ count: 12 });

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    const out = await service.descartarBorradorMes({
      conjuntoId: CONJUNTO,
      anio: 2026,
      mes: 3,
    });

    expect(out).toEqual({ ok: true, eliminadas: 12 });
    expect(prisma.tarea.deleteMany).toHaveBeenCalled();
    expect(prisma.preventivaExcluidaBorrador.deleteMany).toHaveBeenCalled();
    expect(prisma.preventivaBorradorEvento.deleteMany).toHaveBeenCalled();
    expect(prisma.auditoriaEvento.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ accion: 'ELIMINAR_CRONOGRAMA' }),
      }),
    );
  });
});
