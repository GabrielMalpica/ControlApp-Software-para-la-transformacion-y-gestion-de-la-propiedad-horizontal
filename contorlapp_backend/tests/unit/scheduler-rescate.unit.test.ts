import { DiaSemana, Frecuencia } from '@prisma/client';

// Se conserva el resto de schedulerUtils real (es lo que se quiere probar);
// solo se neutraliza la consulta de festivos, que va por SQL crudo.
jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return {
    ...real,
    getFestivosSet: jest.fn().mockResolvedValue(new Set<string>()),
    isFestivoDate: jest.fn().mockResolvedValue(false),
    intentarReemplazoPorPrioridadBaja: jest.fn(
      (...args: any[]) => real.intentarReemplazoPorPrioridadBaja(...args),
    ),
  };
});

import {
  DefinicionTareaPreventivaService,
  ordenarDiasMesPorProximidad,
} from '../../src/services/DefinicionTareaPreventivaService';
import {
  getFestivosSet,
  intentarReemplazoPorPrioridadBaja,
} from '../../src/utils/schedulerUtils';

const intentarReemplazoReal = jest.requireActual(
  '../../src/utils/schedulerUtils',
).intentarReemplazoPorPrioridadBaja;

const CONJUNTO = '9001';
const DIAS_LABORALES = [
  DiaSemana.LUNES,
  DiaSemana.MARTES,
  DiaSemana.MIERCOLES,
  DiaSemana.JUEVES,
  DiaSemana.VIERNES,
];

const ymd = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/**
 * Prisma falso con una agenda en memoria.
 * `diasOcupados` lista los dias (YYYY-MM-DD) en los que el operario ya tiene
 * la jornada entera comprometida.
 */
function construirPrisma(opts: {
  diasOcupados: string[];
  duracionMinutosFija: number;
  prioridad: number;
  diaMesProgramado: number;
}) {
  const tareasCreadas: any[] = [];
  const excluidasCreadas: any[] = [];
  const eventos: any[] = [];
  let secuencia = 1000;

  const ocupacionDelDia = (dia: string) =>
    opts.diasOcupados.includes(dia)
      ? [
          {
            id: 1,
            prioridad: 1,
            fechaInicio: new Date(`${dia}T08:00:00`),
            fechaFin: new Date(`${dia}T16:00:00`),
            duracionMinutos: 480,
            borrador: true,
            estado: 'ASIGNADA',
            grupoPlanId: null,
            bloqueIndex: null,
            bloquesTotales: null,
            operarios: [{ id: 'op-1' }],
          },
        ]
      : [];

  const prisma: any = {
    tareasCreadas,
    excluidasCreadas,
    eventos,

    definicionTareaPreventiva: {
      findMany: jest.fn().mockResolvedValue([
        {
          id: 77,
          conjuntoId: CONJUNTO,
          descripcion: 'Lavado de fachada',
          frecuencia: Frecuencia.MENSUAL,
          diaSemanaProgramado: DiaSemana.LUNES,
          diaMesProgramado: opts.diaMesProgramado,
          prioridad: opts.prioridad,
          duracionMinutosFija: opts.duracionMinutosFija,
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
        },
      ]),
      findUnique: jest.fn().mockResolvedValue(null),
      // Snapshot usado al crear una excluida.
      findFirst: jest.fn().mockResolvedValue({
        id: 77,
        conjuntoId: CONJUNTO,
        descripcion: 'Lavado de fachada',
        frecuencia: Frecuencia.MENSUAL,
        diaSemanaProgramado: DiaSemana.LUNES,
        prioridad: opts.prioridad,
        ubicacionId: 1,
        elementoId: 2,
        supervisorId: null,
        supervisor: null,
        ubicacion: { nombre: 'Torre A' },
        elemento: { nombre: 'Fachada' },
        operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
      }),
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
      findFirst: jest.fn(async ({ where }: any) =>
        DIAS_LABORALES.includes(where.dia)
          ? {
              horaApertura: '08:00',
              horaCierre: '16:00',
              descansoInicio: null,
              descansoFin: null,
            }
          : null,
      ),
      findUnique: jest.fn(async ({ where }: any) =>
        DIAS_LABORALES.includes(where.conjuntoId_dia.dia)
          ? {
              horaApertura: '08:00',
              horaCierre: '16:00',
              descansoInicio: null,
              descansoFin: null,
            }
          : null,
      ),
    },

    tarea: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      count: jest.fn().mockResolvedValue(0),
      findFirst: jest.fn().mockResolvedValue(null),
      findMany: jest.fn(async ({ where }: any) => {
        // Consulta de agenda del dia (buildAgendaPorOperarioDia / minutosAsignadosEnSemana).
        const desde: Date | undefined = where?.fechaFin?.gte ?? where?.fechaInicio?.gte;
        if (!desde) return tareasCreadas;
        const hasta: Date | undefined = where?.fechaInicio?.lte ?? where?.fechaFin?.lte;

        const consultaMesCompleto =
          hasta != null && ymd(desde) !== ymd(hasta);
        const preexistentes = consultaMesCompleto
          ? opts.diasOcupados
              .filter((dia) => {
                const fecha = new Date(`${dia}T12:00:00`);
                return fecha >= desde && (!hasta || fecha <= hasta);
              })
              .flatMap(ocupacionDelDia)
          : ocupacionDelDia(ymd(desde));
        const enRango = tareasCreadas.filter(
          (t) => (!hasta || t.fechaInicio <= hasta) && t.fechaFin >= desde,
        );
        return [...preexistentes, ...enRango].filter(
          (t: any) =>
            !where?.prioridad?.in || where.prioridad.in.includes(t.prioridad),
        );
      }),
      create: jest.fn(async ({ data }: any) => {
        const creada = {
          ...data,
          operarios: data.operarios?.connect ?? data.operarios ?? [],
          id: ++secuencia,
        };
        tareasCreadas.push(creada);
        return creada;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const tarea = tareasCreadas.find((t) => t.id === where.id);
        if (tarea) Object.assign(tarea, data);
        return tarea;
      }),
    },

    preventivaExcluidaBorrador: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(async ({ data }: any) => {
        const creada = { ...data, id: ++secuencia };
        excluidasCreadas.push(creada);
        return creada;
      }),
    },

    preventivaBorradorEvento: {
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return { ...data, id: ++secuencia };
      }),
    },

    // Operario a jornada completa y sin restricciones de disponibilidad.
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
    empresa: { findFirst: jest.fn().mockResolvedValue({ limiteHorasSemana: 48 }) },

    auditoriaEvento: {
      create: jest.fn().mockResolvedValue({}),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },

    $queryRaw: jest.fn().mockResolvedValue([]),
  };

  return prisma;
}

describe('generarBorradorMensual - fase de rescate', () => {
  beforeEach(() => {
    jest.mocked(getFestivosSet).mockResolvedValue(new Set<string>());
    jest
      .mocked(intentarReemplazoPorPrioridadBaja)
      .mockImplementation(intentarReemplazoReal);
  });

  test('PU-R00 - recorre el mes por proximidad sin incluir meses vecinos', () => {
    const ordenados = ordenarDiasMesPorProximidad({
      dias: [
        new Date(2026, 7, 15),
        new Date(2026, 7, 20),
        new Date(2026, 8, 1),
        new Date(2026, 7, 17),
        new Date(2026, 7, 16),
      ],
      fechaObjetivo: new Date(2026, 7, 16),
      periodoAnio: 2026,
      periodoMes: 8,
    });

    expect(ordenados.map(ymd)).toEqual([
      '2026-08-16',
      '2026-08-17',
      '2026-08-15',
      '2026-08-20',
    ]);
  });

  test('PU-R00B - descarta por completo un dia que ya tiene la misma tarea', () => {
    const service = new DefinicionTareaPreventivaService({} as any) as any;
    service.registrarOcurrenciaDefinicionDiaScheduler({
      definicionId: 77,
      ocurrenciaPlanId: 'ocurrencia-anterior',
      bloques: [
        {
          fechaInicio: new Date(2026, 2, 3, 8),
          fechaFin: new Date(2026, 2, 3, 9),
        },
      ],
    });

    const priorizados = service.priorizarDiasSinRepetirDefinicion({
      dias: [new Date(2026, 2, 3), new Date(2026, 2, 4)],
      definicionId: 77,
      ocurrenciaPlanId: 'ocurrencia-nueva',
    });

    expect(priorizados.map(ymd)).toEqual(['2026-03-04']);
  });

  test('PU-R0 - una P2 en festivo se rescata en otro día hábil del mes', async () => {
    jest.mocked(getFestivosSet).mockResolvedValue(new Set(['2026-03-02']));
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 120,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
  });

  test('PU-R0A - la cobertura mínima P3 mueve su primera ocurrencia festiva', async () => {
    jest.mocked(getFestivosSet).mockResolvedValue(new Set(['2026-03-02']));
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 120,
      prioridad: 3,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
  });

  test('PU-R0B - una P1 en festivo se programa el siguiente dia habil', async () => {
    jest.mocked(getFestivosSet).mockResolvedValue(new Set(['2026-03-02']));
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 120,
      prioridad: 1,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
    expect(prisma.excluidasCreadas).toHaveLength(0);
  });

  test('PU-R0C - una P1 no extiende la jornada y se reubica en un día válido', async () => {
    const prisma = construirPrisma({
      diasOcupados: ['2026-03-02'],
      duracionMinutosFija: 120,
      prioridad: 1,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
    expect(prisma.tareasCreadas[0].fechaInicio.getHours()).toBe(8);
    expect(prisma.tareasCreadas[0].fechaFin.getHours()).toBeLessThanOrEqual(16);
    expect(prisma.excluidasCreadas).toHaveLength(0);
  });

  test('PU-R0D - una P1 prueba reemplazos en días posteriores y anteriores del mes', async () => {
    const todosLosDias = Array.from(
      { length: 31 },
      (_, index) => `2026-03-${String(index + 1).padStart(2, '0')}`,
    );
    const prisma = construirPrisma({
      diasOcupados: todosLosDias,
      duracionMinutosFija: 120,
      prioridad: 1,
      diaMesProgramado: 16,
    });
    prisma.tarea.findUnique = jest.fn(async ({ where }: any) => ({
      id: where.id,
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
      definicionId: where.id,
      ocurrenciaPlanId: null,
      descripcion: `Preventiva desplazada ${where.id}`,
      frecuencia: Frecuencia.MENSUAL,
      diaSemanaProgramado: DiaSemana.VIERNES,
      prioridad: 3,
      duracionMinutos: 60,
      fechaInicio: new Date(2026, 2, 13, 8),
      fechaFin: new Date(2026, 2, 13, 9),
      fechaInicioOriginal: null,
      ubicacionId: 1,
      ubicacion: { nombre: 'Torre A' },
      elementoId: 2,
      elemento: { nombre: 'Pasillo' },
      supervisorId: null,
      supervisor: null,
      operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
    }));
    prisma.tarea.delete = jest.fn().mockResolvedValue({});

    const fechasIntentadas: string[] = [];
    const reemplazoMock = jest
      .mocked(intentarReemplazoPorPrioridadBaja)
      .mockImplementation(async (params: any) => {
        const fecha = ymd(params.fechaDia);
        fechasIntentadas.push(fecha);
        if (fecha !== '2026-03-13') {
          return { ok: false, reason: 'SIN_HUECO' } as any;
        }
        return {
          ok: true,
          nuevaTareaIds: [7001, 7002],
          reprogramadasIds: [501, 502],
          bloques: [
            { i: 8 * 60, f: 9 * 60 },
            { i: 10 * 60, f: 11 * 60 },
          ],
        } as any;
      });

    try {
      const service = new DefinicionTareaPreventivaService(prisma);
      const { creadas } = await service.generarBorradorMensual({
        conjuntoId: CONJUNTO,
        periodoAnio: 2026,
        periodoMes: 3,
      });

      expect(creadas).toBe(2);
      expect(fechasIntentadas).toContain('2026-03-17');
      expect(fechasIntentadas).toContain('2026-03-13');
      expect(fechasIntentadas.every((fecha) => fecha.startsWith('2026-03-'))).toBe(true);
      expect(prisma.tarea.delete).toHaveBeenCalledTimes(2);
      expect(prisma.excluidasCreadas).toHaveLength(2);
    } finally {
      reemplazoMock.mockImplementation(intentarReemplazoReal);
    }
  });

  test('PU-R1 - una P3 sin espacio objetivo aprovecha el siguiente dia habil', async () => {
    // Lunes 2 de marzo de 2026 completamente ocupado; el martes 3 esta libre.
    const prisma = construirPrisma({
      diasOcupados: ['2026-03-02'],
      duracionMinutosFija: 120,
      prioridad: 3,
      diaMesProgramado: 2,
    });

    const service = new DefinicionTareaPreventivaService(prisma, {
      id: 'ger-1',
      rol: 'gerente',
      nombre: 'Ana',
    });

    const { creadas, novedades } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);

    const tarea = prisma.tareasCreadas[0];
    expect(ymd(tarea.fechaInicio)).toBe('2026-03-03');
    expect(tarea.definicionId).toBe(77);
    expect(tarea.diaSemanaProgramado).toBe(DiaSemana.LUNES);

    const reubicacion = novedades.find((n) => n.tipo === 'REUBICADA_EN_PERIODO') as any;
    expect(reubicacion).toBeDefined();
    expect(reubicacion.fechaObjetivo).toBe('2026-03-02');
    expect(reubicacion.fecha).toBe('2026-03-03');

    // La reubicacion queda persistida, no solo en la respuesta HTTP.
    expect(prisma.eventos.some((e: any) => e.tipo === 'REUBICADA_EN_PERIODO')).toBe(true);
  });

  test('PU-R1B - una P2 sin hueco el lunes aprovecha el martes de la misma semana', async () => {
    const prisma = construirPrisma({
      diasOcupados: ['2026-03-02'],
      duracionMinutosFija: 120,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
  });

  test('PU-R1C - también busca hacia atrás cuando los días posteriores están llenos', async () => {
    const prisma = construirPrisma({
      diasOcupados: [
        '2026-03-04',
        '2026-03-05',
        '2026-03-06',
        '2026-03-07',
      ],
      duracionMinutosFija: 120,
      prioridad: 2,
      diaMesProgramado: 4,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-03');
  });

  test('PU-R1D - al final del mes busca hacia atrás sin salir del periodo', async () => {
    const prisma = construirPrisma({
      diasOcupados: ['2026-08-31'],
      duracionMinutosFija: 120,
      prioridad: 2,
      diaMesProgramado: 31,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 8,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(prisma.tareasCreadas[0]).toMatchObject({
      periodoAnio: 2026,
      periodoMes: 8,
    });
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-08-28');
  });

  test('PU-R1E - P2 puede rescatarse en otra semana del mismo mes', async () => {
    const prisma = construirPrisma({
      diasOcupados: [
        '2026-03-02',
        '2026-03-03',
        '2026-03-04',
        '2026-03-05',
        '2026-03-06',
      ],
      duracionMinutosFija: 120,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(ymd(prisma.tareasCreadas[0].fechaInicio)).toBe('2026-03-09');
  });

  test('PU-R2 - una P3 sin espacio en todo el mes queda registrada como excluida', async () => {
    // Todos los dias habiles de marzo 2026 ocupados.
    const todos = Array.from({ length: 31 }, (_, i) => `2026-03-${String(i + 1).padStart(2, '0')}`);
    const prisma = construirPrisma({
      diasOcupados: todos,
      duracionMinutosFija: 120,
      prioridad: 3,
      diaMesProgramado: 2,
    });

    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas, novedades } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(0);
    expect(prisma.excluidasCreadas).toHaveLength(1);
    expect(prisma.excluidasCreadas[0]).toMatchObject({
      motivoTipo: 'SIN_HUECO',
      prioridad: 3,
      defId: 77,
      diaSemanaProgramado: DiaSemana.LUNES,
    });
    expect(novedades.some((n) => n.tipo === 'SIN_HUECO')).toBe(true);
  });

  test('PU-R3 - prefiere otro dia antes que fragmentar una tarea en tres bloques', async () => {
    // Lunes 2 con libres 08:00-09:00, 10:00-11:00 y 14:00-16:00 (4h en total).
    // Ninguna pareja de huecos suma las 4h: solo se resuelve partiendo en tres,
    // algo que la fase A (maximo 2 bloques) no puede hacer.
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 240,
      prioridad: 2,
      diaMesProgramado: 2,
    });

    prisma.tarea.findMany = jest.fn(async ({ where }: any) => {
      const desde: Date | undefined = where?.fechaFin?.gte ?? where?.fechaInicio?.gte;
      if (!desde) return prisma.tareasCreadas;
      const hasta: Date | undefined = where?.fechaInicio?.lte ?? where?.fechaFin?.lte;

      const consultaMesCompleto = hasta != null && ymd(desde) !== ymd(hasta);
      const ocupacionFragmentada =
        ymd(desde) === '2026-03-02' || consultaMesCompleto
          ? [
              {
                id: 1,
                fechaInicio: new Date('2026-03-02T09:00:00'),
                fechaFin: new Date('2026-03-02T10:00:00'),
                duracionMinutos: 60,
                operarios: [{ id: 'op-1' }],
              },
              {
                id: 2,
                fechaInicio: new Date('2026-03-02T11:00:00'),
                fechaFin: new Date('2026-03-02T14:00:00'),
                duracionMinutos: 180,
                operarios: [{ id: 'op-1' }],
              },
            ]
          : [];

      const enRango = prisma.tareasCreadas.filter(
        (t: any) => (!hasta || t.fechaInicio <= hasta) && t.fechaFin >= desde,
      );
      return [...ocupacionFragmentada, ...enRango];
    });

    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas, novedades } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(1);
    expect(prisma.excluidasCreadas).toHaveLength(0);

    const horarios = prisma.tareasCreadas.map(
      (t: any) => `${ymd(t.fechaInicio)} ${t.fechaInicio.getHours()}-${t.fechaFin.getHours()}`,
    );
    expect(horarios).toEqual(['2026-03-03 8-12']);

    expect(novedades.some((n) => n.tipo === 'REUBICADA_EN_PERIODO')).toBe(true);
  });

  test('PU-R4 - no reparte una ocurrencia entre varios dias', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 600,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const service = new DefinicionTareaPreventivaService(prisma);

    const { creadas } = await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(creadas).toBe(0);
    expect(prisma.tareasCreadas).toHaveLength(0);
    expect(prisma.excluidasCreadas).toHaveLength(1);
  });

  test('PU-R4B - una P1 de varios dias se completa dentro del mes incluso cerca del cierre', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 960,
      prioridad: 1,
      diaMesProgramado: 29,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        descripcion: 'Pintura de parqueaderos',
        diasParaCompletar: 4,
      },
    ]);
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(prisma.tareasCreadas).toHaveLength(4);
    expect(
      prisma.tareasCreadas.reduce(
        (total: number, tarea: any) => total + tarea.duracionMinutos,
        0,
      ),
    ).toBe(960);
    expect(
      new Set(prisma.tareasCreadas.map((tarea: any) => ymd(tarea.fechaInicio)))
        .size,
    ).toBe(4);
    expect(
      prisma.tareasCreadas.every(
        (tarea: any) =>
          tarea.fechaInicio.getFullYear() === 2026 &&
          tarea.fechaInicio.getMonth() === 2 &&
          tarea.grupoPlanId != null,
      ),
    ).toBe(true);
  });

  test('PU-R4C - reserva las P1 diarias antes de repartir una P1 multidia', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 2100,
      prioridad: 1,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 201,
        descripcion: 'P1 multidia flexible',
        duracionMinutosFija: 2100,
        diasParaCompletar: 5,
      },
      {
        ...base,
        id: 202,
        descripcion: 'P1 diaria rigida',
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija: 30,
        diasParaCompletar: 1,
      },
    ]);
    prisma.operario.findUnique.mockResolvedValue({
      usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
      empresa: { limiteHorasSemana: 35 },
    });
    prisma.conjunto.findUnique.mockResolvedValue({
      limiteHorasSemanaOverride: null,
      empresa: { limiteHorasSemana: 35 },
    });
    prisma.empresa.findFirst.mockResolvedValue({ limiteHorasSemana: 35 });
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    const diarias = prisma.tareasCreadas.filter(
      (tarea: any) => tarea.definicionId === 202,
    );
    const partesMultiDia = prisma.tareasCreadas.filter(
      (tarea: any) => tarea.definicionId === 201,
    );
    expect(diarias).toHaveLength(22);
    expect(new Set(diarias.map((tarea: any) => ymd(tarea.fechaInicio))).size).toBe(
      22,
    );
    expect(partesMultiDia).toHaveLength(5);
    expect(
      partesMultiDia.reduce(
        (total: number, tarea: any) => total + tarea.duracionMinutos,
        0,
      ),
    ).toBe(2100);
    expect(prisma.excluidasCreadas).toHaveLength(0);
  });

  test('PU-R4D - reserva todas las fechas P1 diarias antes de las P1 mensuales', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 240,
      prioridad: 1,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 301,
        descripcion: 'P1 mensual A',
        duracionMinutosFija: 240,
      },
      {
        ...base,
        id: 302,
        descripcion: 'P1 mensual B',
        duracionMinutosFija: 240,
      },
      {
        ...base,
        id: 303,
        descripcion: 'P1 diaria',
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija: 60,
      },
    ]);
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    const diarias = prisma.tareasCreadas.filter(
      (tarea: any) => tarea.definicionId === 303,
    );
    const mensuales = prisma.tareasCreadas.filter(
      (tarea: any) =>
        tarea.definicionId === 301 || tarea.definicionId === 302,
    );
    expect(diarias).toHaveLength(22);
    expect(new Set(diarias.map((tarea: any) => ymd(tarea.fechaInicio))).size).toBe(
      22,
    );
    expect(mensuales).toHaveLength(2);
    expect(prisma.excluidasCreadas).toHaveLength(0);
  });

  test('PU-R5 - da turno a P2 antes de reservar el minimo P3', async () => {
    const diasOcupados = Array.from({ length: 31 }, (_, index) => {
      const fecha = new Date(2026, 2, index + 1);
      return { fecha, key: ymd(fecha) };
    })
      .filter(
        ({ fecha, key }) =>
          fecha.getDay() >= 1 &&
          fecha.getDay() <= 5 &&
          key !== '2026-03-02' &&
          key !== '2026-03-03',
      )
      .map(({ key }) => key);
    const prisma = construirPrisma({
      diasOcupados,
      duracionMinutosFija: 480,
      prioridad: 3,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 78,
        descripcion: 'P2 repetitiva',
        prioridad: 2,
        frecuencia: Frecuencia.DIARIA,
      },
      { ...base, id: 77, descripcion: 'P3 mínima', prioridad: 3 },
    ]);
    prisma.operario.findUnique.mockResolvedValue({
      usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.conjunto.findUnique.mockResolvedValue({
      limiteHorasSemanaOverride: 1000,
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.empresa.findFirst.mockResolvedValue({ limiteHorasSemana: 1000 });
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(prisma.tareasCreadas).toHaveLength(2);
    expect(prisma.tareasCreadas[0]).toMatchObject({
      definicionId: 78,
      prioridad: 2,
      descripcion: 'P2 repetitiva',
    });
    expect(prisma.tareasCreadas[1]).toMatchObject({
      definicionId: 77,
      prioridad: 3,
      descripcion: 'P3 mínima',
    });
  });

  test('PU-R5B - reparte P1 en rondas para que una DIARIA no deje otra P1 en cero', async () => {
    const diasOcupados = Array.from({ length: 31 }, (_, index) => {
      const fecha = new Date(2026, 2, index + 1);
      return { fecha, key: ymd(fecha) };
    })
      .filter(
        ({ fecha, key }) =>
          fecha.getDay() >= 1 &&
          fecha.getDay() <= 5 &&
          key !== '2026-03-02' &&
          key !== '2026-03-03',
      )
      .map(({ key }) => key);
    const prisma = construirPrisma({
      diasOcupados,
      duracionMinutosFija: 480,
      prioridad: 1,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 91,
        descripcion: 'P1 diaria A',
        prioridad: 1,
        frecuencia: Frecuencia.DIARIA,
      },
      {
        ...base,
        id: 92,
        descripcion: 'P1 diaria B',
        prioridad: 1,
        frecuencia: Frecuencia.DIARIA,
      },
    ]);
    prisma.operario.findUnique.mockResolvedValue({
      usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.conjunto.findUnique.mockResolvedValue({
      limiteHorasSemanaOverride: 1000,
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.empresa.findFirst.mockResolvedValue({ limiteHorasSemana: 1000 });
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    expect(
      prisma.tareasCreadas.filter((tarea: any) => tarea.definicionId === 91),
    ).toHaveLength(1);
    expect(
      prisma.tareasCreadas.filter((tarea: any) => tarea.definicionId === 92),
    ).toHaveLength(1);
  });

  test('PU-R5C - completa todas las P1 antes de pasar a P2 y deja P3 al final', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 60,
      prioridad: 3,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 103,
        descripcion: 'P3 mensual',
        prioridad: 3,
      },
      {
        ...base,
        id: 101,
        descripcion: 'P1 diaria',
        prioridad: 1,
        frecuencia: Frecuencia.DIARIA,
      },
      {
        ...base,
        id: 102,
        descripcion: 'P2 mensual',
        prioridad: 2,
      },
    ]);
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    const prioridades = prisma.tareasCreadas.map(
      (tarea: any) => tarea.prioridad,
    );
    expect(
      prioridades.filter((prioridad: number) => prioridad === 1),
    ).toHaveLength(22);
    expect(prioridades.lastIndexOf(1)).toBeLessThan(prioridades.indexOf(2));
    expect(prioridades.indexOf(2)).toBeLessThan(prioridades.indexOf(3));
  });

  test('PU-R5A - DIARIA genera una ocurrencia por jornada configurada, no por dia calendario', async () => {
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 60,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija: 60,
      },
    ]);
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    // Marzo de 2026 tiene 22 dias de lunes a viernes.
    expect(prisma.tareasCreadas).toHaveLength(22);
    expect(prisma.excluidasCreadas).toHaveLength(0);
    expect(
      prisma.tareasCreadas.every(
        (tarea: any) =>
          tarea.fechaInicio.getDay() >= 1 && tarea.fechaInicio.getDay() <= 5,
      ),
    ).toBe(true);
  });

  test('PU-R6 - nunca repite una P3 DIARIA el mismo dia aunque la jornada no alcance para las 5', async () => {
    // Reproduce el caso real reportado: 5 definiciones P3 DIARIA con el mismo
    // operario y jornada de 8h, con duraciones muy dispares (igual que
    // "Aseo del ascensor" 10min vs "Lavado de baños" 90min), a proposito
    // escaladas para que la suma (525min) supere la jornada (480min): ningun
    // dia alcanza para las 5. El sistema ya no rellena ese deficit repitiendo
    // una definicion el mismo dia (eso duplicaria la tarea para el operario);
    // prefiere excluir esa definicion ese dia, aunque el reparto quede
    // desparejo entre definiciones.
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 480,
      prioridad: 3,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    // Mismas proporciones del caso real (10/15/30/30/90 min) escaladas para
    // que la suma supere la jornada de 8h (480min): así ningún día alcanza
    // para las 5 y el reparto por rondas tiene contención real que resolver.
    const duraciones: Record<number, number> = {
      201: 30,
      202: 45,
      203: 90,
      204: 90,
      205: 270,
    };
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue(
      Object.entries(duraciones).map(([id, duracionMinutosFija]) => ({
        ...base,
        id: Number(id),
        descripcion: `P3 ${duracionMinutosFija}min`,
        prioridad: 3,
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija,
      })),
    );
    prisma.operario.findUnique.mockResolvedValue({
      usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.conjunto.findUnique.mockResolvedValue({
      limiteHorasSemanaOverride: 1000,
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.empresa.findFirst.mockResolvedValue({ limiteHorasSemana: 1000 });
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    const conteosPorDefinicion = new Map<number, number>();
    for (const tarea of prisma.tareasCreadas) {
      conteosPorDefinicion.set(
        tarea.definicionId,
        (conteosPorDefinicion.get(tarea.definicionId) ?? 0) + 1,
      );
    }

    // Ninguna definicion se queda en cero...
    for (const id of Object.keys(duraciones).map(Number)) {
      expect(conteosPorDefinicion.get(id) ?? 0).toBeGreaterThan(0);
    }

    // ...pero sobre todo: ningun dia tiene la misma definicion dos veces.
    const definicionesPorDia = new Map<string, Set<number>>();
    for (const tarea of prisma.tareasCreadas) {
      const dia = ymd(tarea.fechaInicio);
      const set = definicionesPorDia.get(dia) ?? new Set<number>();
      expect(set.has(tarea.definicionId)).toBe(false);
      set.add(tarea.definicionId);
      definicionesPorDia.set(dia, set);
    }
  });

  test('PU-R7 - garantiza el minimo de una P2 aunque otra P2 DIARIA vaya primero', async () => {
    // Antes del reparto por rondas, la fase P2 era "TODAS" por definicion:
    // la primera P2 DIARIA agotaba el mes entero antes de que la segunda
    // tuviera su primer intento.
    const prisma = construirPrisma({
      diasOcupados: [],
      duracionMinutosFija: 480,
      prioridad: 2,
      diaMesProgramado: 2,
    });
    const [base] = await prisma.definicionTareaPreventiva.findMany();
    prisma.definicionTareaPreventiva.findMany.mockResolvedValue([
      {
        ...base,
        id: 301,
        descripcion: 'P2 A',
        prioridad: 2,
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija: 300,
      },
      {
        ...base,
        id: 302,
        descripcion: 'P2 B',
        prioridad: 2,
        frecuencia: Frecuencia.DIARIA,
        duracionMinutosFija: 300,
      },
    ]);
    prisma.operario.findUnique.mockResolvedValue({
      usuario: { jornadaLaboral: 'COMPLETA', patronJornada: null },
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.conjunto.findUnique.mockResolvedValue({
      limiteHorasSemanaOverride: 1000,
      empresa: { limiteHorasSemana: 1000 },
    });
    prisma.empresa.findFirst.mockResolvedValue({ limiteHorasSemana: 1000 });
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.generarBorradorMensual({
      conjuntoId: CONJUNTO,
      periodoAnio: 2026,
      periodoMes: 3,
    });

    const conteoA = prisma.tareasCreadas.filter((t: any) => t.definicionId === 301).length;
    const conteoB = prisma.tareasCreadas.filter((t: any) => t.definicionId === 302).length;
    expect(conteoA).toBeGreaterThan(0);
    expect(conteoB).toBeGreaterThan(0);
  });
});
