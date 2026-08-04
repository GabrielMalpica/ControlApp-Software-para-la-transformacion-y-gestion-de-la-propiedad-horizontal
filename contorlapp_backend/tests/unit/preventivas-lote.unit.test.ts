jest.mock('../../src/utils/schedulerUtils', () => {
  const real = jest.requireActual('../../src/utils/schedulerUtils');
  return { ...real, isFestivoDate: jest.fn().mockResolvedValue(false) };
});

import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

const CONJUNTO = '9001';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

function construirPrisma(existentes: Array<{ id: number; descripcion: string }>) {
  const auditorias: any[] = [];

  const tx: any = {
    definicionTareaPreventiva: {
      deleteMany: jest.fn().mockResolvedValue({ count: existentes.length }),
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
    auditorias,
    tx,
    definicionTareaPreventiva: {
      findMany: jest.fn().mockResolvedValue(existentes),
      deleteMany: jest.fn().mockResolvedValue({ count: 1 }),
    },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        auditorias.push(data);
        return data;
      }),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    $transaction: jest.fn(async (cb: any) => cb(tx)),
  };

  return prisma;
}

describe('Borrado en lote de preventivas', () => {
  test('PU-L1 - borra las del conjunto y reporta las que no existen', async () => {
    const prisma = construirPrisma([
      { id: 1, descripcion: 'Lavado de fachada' },
      { id: 2, descripcion: 'Poda de setos' },
    ]);

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    const out = await service.eliminarVarias(CONJUNTO, { ids: [1, 2, 99] });

    expect(out).toEqual({ ok: true, eliminadas: 2, noEncontradas: [99] });
    expect(prisma.tx.definicionTareaPreventiva.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: [1, 2] }, conjuntoId: CONJUNTO },
    });
  });

  test('PU-L2 - audita una entrada por preventiva eliminada', async () => {
    const prisma = construirPrisma([
      { id: 1, descripcion: 'Lavado de fachada' },
      { id: 2, descripcion: 'Poda de setos' },
    ]);

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    await service.eliminarVarias(CONJUNTO, { ids: [1, 2] });

    expect(prisma.auditorias).toHaveLength(2);
    expect(prisma.auditorias.map((a: any) => a.entidadId)).toEqual(['1', '2']);
    expect(prisma.auditorias[0]).toMatchObject({
      accion: 'ELIMINAR',
      modulo: 'PREVENTIVA',
      actorId: 'ger-1',
      conjuntoId: CONJUNTO,
    });
  });

  test('PU-L3 - deduplica los ids repetidos', async () => {
    const prisma = construirPrisma([{ id: 1, descripcion: 'Lavado de fachada' }]);

    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);
    await service.eliminarVarias(CONJUNTO, { ids: [1, 1, 1] });

    expect(prisma.definicionTareaPreventiva.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: { id: { in: [1] }, conjuntoId: CONJUNTO },
      }),
    );
  });

  test('PU-L4 - falla si ninguna pertenece al conjunto', async () => {
    const prisma = construirPrisma([]);
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    await expect(
      service.eliminarVarias(CONJUNTO, { ids: [1, 2] }),
    ).rejects.toThrow(/pertenece a este conjunto/i);
  });

  test('PU-L5 - rechaza una lista vacía', async () => {
    const prisma = construirPrisma([]);
    const service = new DefinicionTareaPreventivaService(prisma, ACTOR);

    await expect(service.eliminarVarias(CONJUNTO, { ids: [] })).rejects.toThrow();
  });
});
