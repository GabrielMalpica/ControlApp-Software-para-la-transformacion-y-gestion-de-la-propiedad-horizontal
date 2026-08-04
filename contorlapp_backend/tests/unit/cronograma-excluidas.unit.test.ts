const asignarTareaConReemplazoV2Mock = jest.fn();
const asignarTareaMock = jest.fn();

jest.mock('../../src/services/GerenteServices', () => ({
  GerenteService: jest.fn().mockImplementation(() => ({
    asignarTareaConReemplazoV2: asignarTareaConReemplazoV2Mock,
    asignarTarea: asignarTareaMock,
  })),
}));

jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return { ...real, isFestivoDate: jest.fn().mockResolvedValue(false) };
});

import {
  CronogramaService,
  purgarExcluidasDeMesesAnteriores,
} from '../../src/services/CronogramaServices';

const CONJUNTO = '9001';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

const excluidaBase = {
  id: 42,
  conjuntoId: CONJUNTO,
  periodoAnio: 2026,
  periodoMes: 3,
  estado: 'PENDIENTE',
  descripcion: 'Lavado de tanque',
  frecuencia: null,
  diaSemanaProgramado: null,
  prioridad: 2,
  duracionMinutos: 180,
  fechaObjetivo: new Date('2026-03-02T00:00:00'),
  ubicacionId: 1,
  elementoId: 2,
  supervisorId: null,
  operariosIds: ['op-1'],
  operariosNombres: ['Pedro'],
  motivoTipo: 'SIN_HUECO',
  motivoMensaje: null,
  metadataJson: null,
};

function prismaConExcluida(overrides: Record<string, any> = {}) {
  const eventos: any[] = [];
  const auditorias: any[] = [];

  const tx: any = {
    preventivaExcluidaBorrador: {
      update: jest.fn(async ({ data }: any) => ({ ...excluidaBase, ...data })),
    },
    preventivaBorradorEvento: {
      create: jest.fn(async ({ data }: any) => {
        eventos.push(data);
        return data;
      }),
    },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        auditorias.push(data);
        return data;
      }),
      createMany: jest.fn(async ({ data }: any) => {
        auditorias.push(...data);
        return { count: data.length };
      }),
    },
  };

  const prisma: any = {
    eventos,
    auditorias,
    tx,
    preventivaExcluidaBorrador: {
      findUnique: jest.fn().mockResolvedValue({ ...excluidaBase }),
      findMany: jest.fn().mockResolvedValue([]),
      deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    preventivaBorradorEvento: { findMany: jest.fn().mockResolvedValue([]) },
    tarea: {
      findMany: jest.fn().mockResolvedValue([]),
      count: jest.fn().mockResolvedValue(1),
    },
    usuario: { findMany: jest.fn().mockResolvedValue([]) },
    conjuntoHorario: { findFirst: jest.fn().mockResolvedValue(null) },
    operario: { findUnique: jest.fn().mockResolvedValue(null) },
    operarioDisponibilidadPeriodo: { findFirst: jest.fn().mockResolvedValue(null) },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        auditorias.push(data);
        return data;
      }),
      createMany: jest.fn(async ({ data }: any) => {
        auditorias.push(...data);
        return { count: data.length };
      }),
    },
    $transaction: jest.fn(async (cb: any) => cb(tx)),
    ...overrides,
  };

  return prisma;
}

describe('Excluidas en el cronograma definitivo', () => {
  beforeEach(() => {
    asignarTareaConReemplazoV2Mock.mockReset();
    asignarTareaMock.mockReset();
  });

  describe('programarExcluidaComoCorrectiva', () => {
    const tareasADesplazar = [
      {
        id: 501,
        descripcion: 'Barrido zona verde',
        fechaInicio: new Date('2026-03-05T08:00:00'),
        fechaFin: new Date('2026-03-05T09:00:00'),
        prioridad: 3,
        operarios: [{ usuario: { nombre: 'Pedro' } }],
      },
      {
        id: 502,
        descripcion: 'Limpieza de pasillos',
        fechaInicio: new Date('2026-03-05T09:00:00'),
        fechaFin: new Date('2026-03-05T11:00:00'),
        prioridad: 3,
        operarios: [{ usuario: { nombre: 'Pedro' } }],
      },
    ];

    test('PU-C1 - desplaza varias tareas y las deja registradas en el evento', async () => {
      const prisma = prismaConExcluida();
      prisma.tarea.findMany.mockResolvedValue(tareasADesplazar);
      asignarTareaConReemplazoV2Mock.mockResolvedValue({
        ok: true,
        createdCorrectivaId: 900,
        reprogramadasIds: [502],
        canceladasIds: [501],
      });

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      const out: any = await service.programarExcluidaComoCorrectiva({
        excluidaId: 42,
        fechaInicio: '2026-03-05T08:00:00',
        reemplazarTareaIds: [501, 502],
        motivoReemplazo: 'Se prioriza el lavado del tanque',
      });

      expect(asignarTareaConReemplazoV2Mock).toHaveBeenCalledWith(
        expect.objectContaining({ reemplazarIds: [501, 502], accionReemplazadas: 'CANCELAR' }),
      );

      expect(out.tareasDesplazadas).toEqual([
        expect.objectContaining({ id: 501, accion: 'CANCELADA' }),
        expect.objectContaining({ id: 502, accion: 'REPROGRAMADA' }),
      ]);

      const evento = prisma.eventos[0];
      expect(evento.tipo).toBe('EXCLUIDA_CORRECTIVA_REEMPLAZO');
      expect(evento.actorId).toBe('ger-1');
      expect(evento.metadataJson.reemplazarTareaIds).toEqual([501, 502]);
      expect(evento.metadataJson.tareasReemplazadas).toHaveLength(2);

      // Una auditoria para la excluida y una por cada tarea desplazada.
      expect(prisma.auditorias.map((a: any) => a.accion)).toEqual([
        'PROGRAMAR_CORRECTIVA',
        'REEMPLAZAR',
        'REEMPLAZAR',
      ]);
    });

    test('PU-C2 - mantiene la compatibilidad con reemplazarTareaId unico', async () => {
      const prisma = prismaConExcluida();
      prisma.tarea.findMany.mockResolvedValue([tareasADesplazar[0]]);
      asignarTareaConReemplazoV2Mock.mockResolvedValue({
        ok: true,
        createdCorrectivaId: 901,
        reprogramadasIds: [],
        canceladasIds: [501],
      });

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      await service.programarExcluidaComoCorrectiva({
        excluidaId: 42,
        fechaInicio: '2026-03-05T08:00:00',
        reemplazarTareaId: 501,
        motivoReemplazo: 'Motivo valido',
      });

      expect(asignarTareaConReemplazoV2Mock).toHaveBeenCalledWith(
        expect.objectContaining({ reemplazarIds: [501] }),
      );
    });

    test('PU-C3 - sin reemplazos usa la asignacion normal', async () => {
      const prisma = prismaConExcluida();
      asignarTareaMock.mockResolvedValue({ ok: true, tareaId: 902 });

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      await service.programarExcluidaComoCorrectiva({
        excluidaId: 42,
        fechaInicio: '2026-03-05T08:00:00',
      });

      expect(asignarTareaMock).toHaveBeenCalled();
      expect(asignarTareaConReemplazoV2Mock).not.toHaveBeenCalled();
      expect(prisma.eventos[0].tipo).toBe('EXCLUIDA_CORRECTIVA_AGENDADA');
    });

    test('PU-C4 - rechaza un motivo de reemplazo demasiado corto', async () => {
      const prisma = prismaConExcluida();
      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);

      await expect(
        service.programarExcluidaComoCorrectiva({
          excluidaId: 42,
          fechaInicio: '2026-03-05T08:00:00',
          reemplazarTareaIds: [501],
          motivoReemplazo: 'x',
        }),
      ).rejects.toThrow();
    });
  });

  describe('reasignarOperarioExcluidaPublicada', () => {
    const horarioAbierto = {
      horaApertura: '08:00',
      horaCierre: '17:00',
      descansoInicio: null,
      descansoFin: null,
    };

    test('PU-C5 - cambia solo la excluida y nunca la definicion preventiva', async () => {
      const prisma = prismaConExcluida();
      prisma.conjuntoHorario.findFirst.mockResolvedValue(horarioAbierto);
      prisma.operario.findUnique.mockResolvedValue({
        id: 'op-2',
        usuario: { nombre: 'Luis Gomez' },
      });
      prisma.definicionTareaPreventiva = { update: jest.fn() };

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      const out: any = await service.reasignarOperarioExcluidaPublicada({
        excluidaId: 42,
        nuevoOperarioId: 'op-2',
        motivo: 'Pedro esta incapacitado',
      });

      expect(out.esExcepcion).toBe(true);
      expect(prisma.definicionTareaPreventiva.update).not.toHaveBeenCalled();

      const update = prisma.tx.preventivaExcluidaBorrador.update.mock.calls[0][0];
      expect(update.data.operariosIds).toEqual(['op-2']);
      expect(update.data.operariosNombres).toEqual(['Luis Gomez']);
      expect(update.data.metadataJson.excepcionOperario).toMatchObject({
        operariosOriginalesIds: ['op-1'],
        nuevoOperarioId: 'op-2',
        motivo: 'Pedro esta incapacitado',
      });

      expect(prisma.eventos[0].tipo).toBe('EXCLUIDA_OPERARIO_EXCEPCION');
      expect(prisma.auditorias[0].accion).toBe('REASIGNAR_OPERARIO');
    });

    test('PU-C6 - rechaza al operario que no tiene ventana libre ese dia', async () => {
      const prisma = prismaConExcluida();
      prisma.conjuntoHorario.findFirst.mockResolvedValue(horarioAbierto);
      prisma.operario.findUnique.mockResolvedValue({
        id: 'op-2',
        usuario: { nombre: 'Luis Gomez' },
      });
      // Jornada completa ocupada: no caben las 3h de la excluida.
      prisma.tarea.findMany.mockResolvedValue([
        {
          fechaInicio: new Date('2026-03-02T08:00:00'),
          fechaFin: new Date('2026-03-02T17:00:00'),
          operarios: [{ id: 'op-2' }],
        },
      ]);

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);

      await expect(
        service.reasignarOperarioExcluidaPublicada({
          excluidaId: 42,
          nuevoOperarioId: 'op-2',
        }),
      ).rejects.toThrow(/no tiene horas libres suficientes/i);
    });

    test('PU-C7 - exige que el cronograma del periodo este publicado', async () => {
      const prisma = prismaConExcluida();
      prisma.tarea.count.mockResolvedValue(0);

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);

      await expect(
        service.reasignarOperarioExcluidaPublicada({
          excluidaId: 42,
          nuevoOperarioId: 'op-2',
        }),
      ).rejects.toThrow(/ya esta publicado/i);
    });
  });

  describe('listarOpcionesReemplazoExcluida', () => {
    test('PU-C8 - propone la combinacion minima de tareas a desplazar', async () => {
      const prisma = prismaConExcluida();
      // Jornada 08:00-12:00 (240 min) totalmente ocupada por dos tareas.
      prisma.conjuntoHorario.findFirst.mockResolvedValue({
        horaApertura: '08:00',
        horaCierre: '12:00',
        descansoInicio: null,
        descansoFin: null,
      });
      prisma.tarea.findMany.mockResolvedValue([
        {
          id: 501,
          descripcion: 'Barrido',
          fechaInicio: new Date('2026-03-05T08:00:00'),
          fechaFin: new Date('2026-03-05T10:00:00'),
          duracionMinutos: 120,
          prioridad: 3,
          tipo: 'PREVENTIVA',
          operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
        },
        {
          id: 502,
          descripcion: 'Limpieza',
          fechaInicio: new Date('2026-03-05T10:00:00'),
          fechaFin: new Date('2026-03-05T12:00:00'),
          duracionMinutos: 120,
          prioridad: 3,
          tipo: 'PREVENTIVA',
          operarios: [{ id: 'op-1', usuario: { nombre: 'Pedro' } }],
        },
      ]);

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      const out: any = await service.listarOpcionesReemplazoExcluida({
        excluidaId: 42,
        fecha: '2026-03-05',
      });

      expect(out.minutosLibresActuales).toBe(0);
      expect(out.minutosFaltantes).toBe(180);
      // 120 no alcanza para 180, hacen falta las dos.
      expect(out.combinacionMinima).toEqual([501, 502]);
      expect(out.alcanzaConDesplazamientos).toBe(true);
      expect(out.opciones).toHaveLength(2);
    });
  });

  describe('informeExcluidasDelPeriodo', () => {
    test('PU-C9 - separa programadas, excepciones y pendientes', async () => {
      const prisma = prismaConExcluida();
      prisma.preventivaBorradorEvento.findMany.mockResolvedValue([
        {
          id: 1,
          tipo: 'EXCLUIDA_CORRECTIVA_REEMPLAZO',
          excluidaId: 42,
          tareaId: 900,
          actorId: 'ger-1',
          actorRol: 'gerente',
          creadoEn: new Date('2026-03-04T10:00:00'),
          metadataJson: {
            fechaInicio: '2026-03-05T08:00:00.000Z',
            motivoReemplazo: 'Se prioriza el tanque',
            tareasReemplazadas: [{ id: 501, accion: 'CANCELADA' }],
          },
        },
        {
          id: 2,
          tipo: 'EXCLUIDA_OPERARIO_EXCEPCION',
          excluidaId: 43,
          tareaId: null,
          actorId: 'ger-1',
          actorRol: 'gerente',
          creadoEn: new Date('2026-03-04T11:00:00'),
          metadataJson: {
            operariosOriginalesNombres: ['Pedro'],
            nuevoOperarioNombre: 'Luis Gomez',
            motivo: 'Incapacidad',
          },
        },
      ]);
      prisma.preventivaExcluidaBorrador.findMany.mockResolvedValue([
        { ...excluidaBase, id: 42, estado: 'AGENDADA' },
        { ...excluidaBase, id: 43, descripcion: 'Poda de jardin' },
      ]);
      prisma.usuario.findMany.mockResolvedValue([{ id: 'ger-1', nombre: 'Ana Perez' }]);

      const service = new CronogramaService(prisma, CONJUNTO, ACTOR);
      const out: any = await service.informeExcluidasDelPeriodo({ anio: 2026, mes: 3 });

      expect(out.programadasPosteriormente).toHaveLength(1);
      expect(out.programadasPosteriormente[0]).toMatchObject({
        excluidaId: 42,
        descripcion: 'Lavado de tanque',
        tareaId: 900,
        actor: { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' },
      });
      expect(out.programadasPosteriormente[0].tareasDesplazadas).toEqual([
        { id: 501, accion: 'CANCELADA' },
      ]);

      expect(out.excepcionesOperario).toHaveLength(1);
      expect(out.excepcionesOperario[0]).toMatchObject({
        operariosOriginales: ['Pedro'],
        operariosNuevos: ['Luis Gomez'],
      });

      // Solo la 43 sigue PENDIENTE.
      expect(out.pendientes.map((p: any) => p.excluidaId)).toEqual([43]);
    });
  });

  describe('purgarExcluidasDeMesesAnteriores', () => {
    test('PU-C10 - borra solo periodos anteriores y puede aplicar a todos los conjuntos', async () => {
      const prisma: any = {
        preventivaExcluidaBorrador: {
          deleteMany: jest.fn().mockResolvedValue({ count: 7 }),
        },
      };

      const eliminadas = await purgarExcluidasDeMesesAnteriores(prisma, { anio: 2026, mes: 4 });

      expect(eliminadas).toBe(7);
      expect(prisma.preventivaExcluidaBorrador.deleteMany).toHaveBeenCalledWith({
        where: {
          OR: [{ periodoAnio: { lt: 2026 } }, { periodoAnio: 2026, periodoMes: { lt: 4 } }],
        },
      });

      await purgarExcluidasDeMesesAnteriores(prisma, {
        conjuntoId: CONJUNTO,
        anio: 2026,
        mes: 4,
      });

      expect(prisma.preventivaExcluidaBorrador.deleteMany).toHaveBeenLastCalledWith({
        where: {
          conjuntoId: CONJUNTO,
          OR: [{ periodoAnio: { lt: 2026 } }, { periodoAnio: 2026, periodoMes: { lt: 4 } }],
        },
      });
    });
  });
});
