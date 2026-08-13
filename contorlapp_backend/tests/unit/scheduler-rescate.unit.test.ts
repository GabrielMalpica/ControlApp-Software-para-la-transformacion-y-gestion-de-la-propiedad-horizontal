import { DiaSemana, Frecuencia } from '@prisma/client';

// Se conserva el resto de schedulerUtils real (es lo que se quiere probar);
// solo se neutraliza la consulta de festivos, que va por SQL crudo.
jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return {
    ...real,
    getFestivosSet: jest.fn().mockResolvedValue(new Set<string>()),
    isFestivoDate: jest.fn().mockResolvedValue(false),
  };
});

import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';
import { getFestivosSet } from '../../src/utils/schedulerUtils';

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

        const preexistentes = ocupacionDelDia(ymd(desde));
        const enRango = tareasCreadas.filter(
          (t) => (!hasta || t.fechaInicio <= hasta) && t.fechaFin >= desde,
        );
        return [...preexistentes, ...enRango].filter(
          (t: any) =>
            !where?.prioridad?.in || where.prioridad.in.includes(t.prioridad),
        );
      }),
      create: jest.fn(async ({ data }: any) => {
        const creada = { ...data, id: ++secuencia };
        tareasCreadas.push(creada);
        return creada;
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
  });

  test.each([2, 3])(
    'PU-R0 - una P%s en festivo pasa directamente a excluidas',
    async (prioridad) => {
      jest.mocked(getFestivosSet).mockResolvedValue(new Set(['2026-03-02']));
      const prisma = construirPrisma({
        diasOcupados: [],
        duracionMinutosFija: 120,
        prioridad,
        diaMesProgramado: 2,
      });
      const service = new DefinicionTareaPreventivaService(prisma);

      const { creadas } = await service.generarBorradorMensual({
        conjuntoId: CONJUNTO,
        periodoAnio: 2026,
        periodoMes: 3,
      });

      expect(creadas).toBe(0);
      expect(prisma.excluidasCreadas).toHaveLength(1);
      expect(prisma.excluidasCreadas[0]).toMatchObject({
        prioridad,
        motivoTipo: 'FESTIVO_OMITIDO',
      });
    },
  );

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

  test('PU-R1B - una P2 sin hueco ni P3 queda excluida en su dia objetivo', async () => {
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

    expect(creadas).toBe(0);
    expect(prisma.excluidasCreadas).toHaveLength(1);
    expect(prisma.excluidasCreadas[0]).toMatchObject({
      prioridad: 2,
      motivoTipo: 'SIN_CANDIDATAS',
    });
    expect(ymd(prisma.excluidasCreadas[0].fechaObjetivo)).toBe('2026-03-02');
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

  test('PU-R3 - una tarea que no cabe entera se divide en tres bloques del mismo dia', async () => {
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

      const ocupacionFragmentada =
        ymd(desde) === '2026-03-02'
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

    expect(creadas).toBe(3);
    expect(prisma.excluidasCreadas).toHaveLength(0);

    const horarios = prisma.tareasCreadas.map(
      (t: any) => `${ymd(t.fechaInicio)} ${t.fechaInicio.getHours()}-${t.fechaFin.getHours()}`,
    );
    expect(horarios).toEqual([
      '2026-03-02 8-9',
      '2026-03-02 10-11',
      '2026-03-02 14-16',
    ]);

    // Al admitir todos los huecos desde el primer intento ya no necesita pasar
    // por la fase de rescate ni reportarse como reubicada.
    expect(novedades.some((n) => n.tipo === 'REUBICADA_EN_PERIODO')).toBe(false);
  });
});
