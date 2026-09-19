import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

const CONJUNTO = '9001';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

describe('acciones manuales del borrador preventivo', () => {
  test('divide manualmente una excluida cuando los minutos completan la duracion', async () => {
    const excluida = {
      id: 50,
      conjuntoId: CONJUNTO,
      estado: 'PENDIENTE',
      duracionMinutos: 180,
      metadataJson: null,
      periodoAnio: 2026,
      periodoMes: 9,
      descripcion: 'Lavado de tanque',
    };
    const prisma: any = {
      preventivaExcluidaBorrador: {
        findUnique: jest.fn().mockResolvedValue(excluida),
        update: jest.fn(async ({ data }: any) => ({ ...excluida, ...data })),
      },
      preventivaBorradorEvento: { create: jest.fn().mockResolvedValue({}) },
      auditoriaEvento: { create: jest.fn().mockResolvedValue({}) },
    };
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    const resultado = await service.dividirExcluidaManual({
      conjuntoId: CONJUNTO,
      excluidaId: excluida.id,
      bloques: [{ duracionMinutos: 60 }, { duracionMinutos: 120 }],
    });

    expect(resultado.ok).toBe(true);
    const metadata = prisma.preventivaExcluidaBorrador.update.mock.calls[0][0]
      .data.metadataJson;
    expect(metadata.divisionManual).toMatchObject({
      activa: true,
      bloques: [
        { id: 'b1', orden: 1, duracionMinutos: 60, estado: 'PENDIENTE' },
        { id: 'b2', orden: 2, duracionMinutos: 120, estado: 'PENDIENTE' },
      ],
    });
  });

  test('al excluir un bloque multidia conserva sus hermanos y libera solo su maquinaria', async () => {
    const base = {
      descripcion: 'Limpieza profunda',
      conjuntoId: CONJUNTO,
      borrador: true,
      tipo: 'PREVENTIVA',
      estado: 'ASIGNADA',
      periodoAnio: 2026,
      periodoMes: 9,
      ocurrenciaPlanId: 'OC-1',
      grupoPlanId: 'GRP-1',
      definicionId: 77,
      frecuencia: 'MENSUAL',
      diaSemanaProgramado: null,
      prioridad: 1,
      fechaInicioOriginal: null,
      ubicacionId: 1,
      ubicacion: { nombre: 'Zona comun' },
      elementoId: 2,
      elemento: { nombre: 'Pisos', parent: null },
      supervisorId: null,
      supervisor: null,
      operarios: [
        { id: 'op-1', usuario: { nombre: 'Ana' } },
        { id: 'op-2', usuario: { nombre: 'Luis' } },
      ],
    };
    const bloques = [
      {
        ...base,
        id: 60,
        fechaInicio: new Date(2026, 8, 7, 8),
        fechaFin: new Date(2026, 8, 7, 9),
        duracionMinutos: 60,
      },
      {
        ...base,
        id: 61,
        fechaInicio: new Date(2026, 8, 8, 8),
        fechaFin: new Date(2026, 8, 8, 10),
        duracionMinutos: 120,
      },
    ];
    const prisma: any = {
      tarea: {
        findFirst: jest.fn().mockResolvedValue(bloques[0]),
        findMany: jest.fn(async ({ where }: any) =>
          bloques.filter((bloque) => bloque.grupoPlanId === where.grupoPlanId),
        ),
        findUnique: jest.fn().mockResolvedValue(bloques[0]),
        update: jest.fn(async ({ where, data }: any) => {
          const bloque = bloques.find((item) => item.id === where.id);
          Object.assign(bloque!, data);
          return bloque;
        }),
        deleteMany: jest.fn(async ({ where }: any) => {
          const index = bloques.findIndex((item) => item.id === where.id.in[0]);
          if (index >= 0) bloques.splice(index, 1);
          return { count: index >= 0 ? 1 : 0 };
        }),
      },
      preventivaExcluidaBorrador: {
        create: jest.fn(async ({ data }: any) => ({ ...data, id: 500 })),
      },
      preventivaBorradorEvento: { create: jest.fn().mockResolvedValue({}) },
      preventivaOcurrenciaPlan: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      usoMaquinaria: { deleteMany: jest.fn().mockResolvedValue({ count: 1 }) },
      auditoriaEvento: { create: jest.fn().mockResolvedValue({}) },
      $transaction: jest.fn(async (callback: any) => callback(prisma)),
    };
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    await service.eliminarBloqueBorrador(CONJUNTO, 60);

    expect(prisma.preventivaExcluidaBorrador.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          duracionMinutos: 60,
          motivoTipo: 'MANUAL_ELIMINADA',
          metadataJson: {
            tareaIdsOriginales: [60],
            bloquesEliminados: 1,
          },
        }),
      }),
    );
    expect(prisma.usoMaquinaria.deleteMany).toHaveBeenCalledWith({
      where: { tareaId: { in: [60] } },
    });
    expect(prisma.tarea.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: [60] } },
    });
    expect(bloques).toHaveLength(1);
    expect(bloques[0]).toMatchObject({
      id: 61,
      grupoPlanId: null,
      bloqueIndex: null,
      bloquesTotales: null,
    });
  });
});
