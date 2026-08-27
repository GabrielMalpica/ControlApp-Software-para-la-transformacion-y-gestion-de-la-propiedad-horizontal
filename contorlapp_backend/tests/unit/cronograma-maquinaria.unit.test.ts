import { EstadoMaquinaria, TipoMaquinaria } from '@prisma/client';

import { CronogramaMaquinariaService } from '../../src/services/CronogramaMaquinariaService';

const EMPRESA = 'EMP-1';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

function tarea(overrides: Record<string, any> = {}) {
  return {
    id: 501,
    descripcion: 'Guadañada zonas verdes',
    fechaInicio: new Date(2026, 2, 5, 8),
    fechaFin: new Date(2026, 2, 5, 12),
    grupoPlanId: null,
    periodoAnio: 2026,
    periodoMes: 3,
    conjuntoId: '9001',
    conjunto: { nombre: 'Conjunto Palmas' },
    operarios: [{ usuario: { nombre: 'Pedro' } }],
    maquinariaPlanJson: [{ tipo: 'GUADANIA', cantidad: 1 }],
    usoMaquinarias: [],
    ...overrides,
  };
}

function construirPrisma(overrides: Record<string, any> = {}) {
  const auditorias: any[] = [];

  const tx: any = {
    usoMaquinaria: {
      create: jest.fn().mockResolvedValue({ id: 9001 }),
      delete: jest.fn().mockResolvedValue({}),
    },
    maquinariaConjunto: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        auditorias.push(data);
        return data;
      }),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
  };

  const prisma: any = {
    auditorias,
    tx,
    conjunto: {
      findMany: jest.fn().mockResolvedValue([{ nit: '9001' }, { nit: '9002' }]),
    },
    tarea: { findMany: jest.fn().mockResolvedValue([]) },
    maquinaria: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
    },
    usoMaquinaria: {
      findFirst: jest.fn().mockResolvedValue(null),
      findUnique: jest.fn().mockResolvedValue(null),
      count: jest.fn().mockResolvedValue(0),
    },
    auditoriaEvento: {
      create: jest.fn(async ({ data }: any) => {
        auditorias.push(data);
        return data;
      }),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
    },
    $transaction: jest.fn(async (cb: any) => cb(tx)),
    ...overrides,
  };

  return prisma;
}

describe('CronogramaMaquinariaService', () => {
  describe('listarNecesidades', () => {
    test('PU-CM1 - agrupa por tipo, conjunto y día sumando cantidades', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({ id: 501, maquinariaPlanJson: [{ tipo: 'GUADANIA', cantidad: 2 }] }),
        tarea({
          id: 502,
          descripcion: 'Guadañada perimetro',
          maquinariaPlanJson: [{ tipo: 'GUADANIA', cantidad: 1 }],
        }),
        // Otro dia: grupo distinto.
        tarea({
          id: 503,
          fechaInicio: new Date(2026, 2, 6, 8),
          fechaFin: new Date(2026, 2, 6, 10),
        }),
      ]);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({ anio: 2026, mes: 3 });

      expect(out.necesidades).toHaveLength(2);

      const dia5 = out.necesidades.find((n) => n.fecha.getDate() === 5)!;
      expect(dia5.tipo).toBe(TipoMaquinaria.GUADANIA);
      expect(dia5.conjuntoNombre).toBe('Conjunto Palmas');
      expect(dia5.cantidadRequerida).toBe(3);
      expect(dia5.pendientes).toBe(3);
      expect(dia5.tareas.map((t) => t.tareaId)).toEqual([501, 502]);
    });

    test('PU-CM2 - descuenta las máquinas ya asignadas', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({
          maquinariaPlanJson: [{ tipo: 'GUADANIA', cantidad: 2 }],
          usoMaquinarias: [
            {
              id: 77,
              fechaInicio: new Date(2026, 2, 4),
              fechaFin: new Date(2026, 2, 7),
              maquinaria: {
                id: 12,
                nombre: 'Guadaña Stihl',
                marca: 'Stihl',
                tipo: TipoMaquinaria.GUADANIA,
              },
            },
          ],
        }),
      ]);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({ anio: 2026, mes: 3 });

      expect(out.necesidades[0].cantidadRequerida).toBe(2);
      expect(out.necesidades[0].asignaciones).toHaveLength(1);
      expect(out.necesidades[0].pendientes).toBe(1);
    });

    test('PU-CM3 - una máquina de otro tipo no cuenta como asignada', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({
          usoMaquinarias: [
            {
              id: 78,
              fechaInicio: new Date(2026, 2, 4),
              fechaFin: new Date(2026, 2, 7),
              maquinaria: {
                id: 30,
                nombre: 'Taladro',
                marca: 'Bosch',
                tipo: TipoMaquinaria.TALADRO,
              },
            },
          ],
        }),
      ]);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({ anio: 2026, mes: 3 });

      expect(out.necesidades[0].asignaciones).toHaveLength(0);
      expect(out.necesidades[0].pendientes).toBe(1);
    });

    test('PU-CM4 - soloPendientes oculta las necesidades ya cubiertas', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({
          usoMaquinarias: [
            {
              id: 77,
              fechaInicio: new Date(2026, 2, 4),
              fechaFin: new Date(2026, 2, 7),
              maquinaria: {
                id: 12,
                nombre: 'Guadaña Stihl',
                marca: 'Stihl',
                tipo: TipoMaquinaria.GUADANIA,
              },
            },
          ],
        }),
      ]);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({
        anio: 2026,
        mes: 3,
        soloPendientes: true,
      });

      expect(out.necesidades).toHaveLength(0);
    });
  });

  describe('asignarMaquinaria', () => {
    const maquinaGuadania = {
      id: 12,
      nombre: 'Guadaña Stihl FS-38',
      marca: 'Stihl',
      tipo: TipoMaquinaria.GUADANIA,
      estado: EstadoMaquinaria.OPERATIVA,
    };

    test('PU-CM5 - crea un único uso sobre la tarea representante y audita', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea({ id: 501 }), tarea({ id: 502 })]);
      prisma.maquinaria.findFirst.mockResolvedValue(maquinaGuadania);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);
      const out: any = await service.asignarMaquinaria({
        tareaIds: [501, 502],
        maquinariaId: 12,
      });

      expect(out.ok).toBe(true);
      expect(out.usoId).toBe(9001);
      expect(prisma.tx.usoMaquinaria.create).toHaveBeenCalledTimes(1);

      const data = prisma.tx.usoMaquinaria.create.mock.calls[0][0].data;
      expect(data.tarea.connect.id).toBe(501);
      expect(data.maquinaria.connect.id).toBe(12);

      expect(prisma.auditorias[0]).toMatchObject({
        accion: 'ASIGNAR_MAQUINARIA',
        actorId: 'ger-1',
        conjuntoId: '9001',
      });
    });

    test('PU-CM6 - rechaza una máquina de tipo distinto al requerido', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.maquinaria.findFirst.mockResolvedValue({
        ...maquinaGuadania,
        id: 30,
        nombre: 'Taladro',
        tipo: TipoMaquinaria.TALADRO,
      });

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501], maquinariaId: 30 }),
      ).rejects.toThrow(/no requieren ese tipo de máquina/i);
    });

    test('PU-CM7 - rechaza una máquina que no está operativa', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.maquinaria.findFirst.mockResolvedValue({
        ...maquinaGuadania,
        estado: EstadoMaquinaria.EN_REPARACION,
      });

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501], maquinariaId: 12 }),
      ).rejects.toThrow(/no está operativa/i);
    });

    test('PU-CM8 - un solape en la ventana logística lanza el error 409 de maquinaria', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.maquinaria.findFirst.mockResolvedValue(maquinaGuadania);
      prisma.usoMaquinaria.findFirst.mockResolvedValue({
        id: 88,
        fechaInicio: new Date(2026, 2, 4),
        fechaFin: new Date(2026, 2, 7),
        tarea: {
          id: 999,
          descripcion: 'Otra guadañada',
          estado: 'ASIGNADA',
          conjuntoId: '9002',
          conjunto: { nombre: 'Conjunto Sol' },
        },
      });

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501], maquinariaId: 12 }),
      ).rejects.toMatchObject({
        status: 409,
        reason: 'MAQUINARIA_NO_DISPONIBLE',
      });

      expect(prisma.tx.usoMaquinaria.create).not.toHaveBeenCalled();
    });

    test('PU-CM9 - no permite mezclar tareas de conjuntos distintos', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({ id: 501, conjuntoId: '9001' }),
        tarea({ id: 502, conjuntoId: '9002' }),
      ]);
      prisma.maquinaria.findFirst.mockResolvedValue(maquinaGuadania);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501, 502], maquinariaId: 12 }),
      ).rejects.toThrow(/mismo conjunto/i);
    });

    test('PU-CM10 - rechaza maquinaria que no pertenece a la empresa', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.maquinaria.findFirst.mockResolvedValue(null);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501], maquinariaId: 999 }),
      ).rejects.toThrow(/no existe para esta empresa/i);
      expect(prisma.maquinaria.findFirst).toHaveBeenCalledWith(
        expect.objectContaining({
          where: expect.objectContaining({ id: 999 }),
        }),
      );
    });

    test('PU-CM11 - no permite sobreasignar una necesidad ya cubierta', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.maquinaria.findFirst.mockResolvedValue(maquinaGuadania);
      prisma.usoMaquinaria.count
        .mockResolvedValueOnce(1)
        .mockResolvedValueOnce(0);

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarMaquinaria({ tareaIds: [501], maquinariaId: 12 }),
      ).rejects.toThrow(/completamente cubierta/i);
      expect(prisma.tx.usoMaquinaria.create).not.toHaveBeenCalled();
    });
  });

  describe('liberarAsignacion', () => {
    test('PU-CM12 - borra el uso, suelta la asignación del conjunto y audita', async () => {
      const prisma = construirPrisma();
      prisma.usoMaquinaria.findUnique.mockResolvedValue({
        id: 9001,
        maquinariaId: 12,
        tarea: {
          id: 501,
          descripcion: 'Guadañada zonas verdes',
          conjuntoId: '9001',
          periodoAnio: 2026,
          periodoMes: 3,
        },
      });

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);
      const out = await service.liberarAsignacion({ usoId: 9001 });

      expect(out).toEqual({ ok: true });
      expect(prisma.tx.usoMaquinaria.delete).toHaveBeenCalledWith({
        where: { id: 9001 },
      });
      expect(prisma.tx.maquinariaConjunto.updateMany).toHaveBeenCalledWith(
        expect.objectContaining({ data: { tareaId: null } }),
      );
      expect(prisma.auditorias[0].accion).toBe('LIBERAR_MAQUINARIA');
    });

    test('PU-CM13 - rechaza una asignación de otra empresa', async () => {
      const prisma = construirPrisma();
      prisma.usoMaquinaria.findUnique.mockResolvedValue({
        id: 9001,
        maquinariaId: 12,
        tarea: { id: 501, descripcion: 'X', conjuntoId: 'AJENO' },
      });

      const service = new CronogramaMaquinariaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.liberarAsignacion({ usoId: 9001 }),
      ).rejects.toThrow(/no existe para esta empresa/i);
    });
  });
});
