import { CronogramaHerramientaService } from '../../src/services/CronogramaHerramientaService';

const EMPRESA = 'EMP-1';
const ACTOR = { id: 'ger-1', rol: 'gerente', nombre: 'Ana Perez' };

function tarea(overrides: Record<string, any> = {}) {
  return {
    id: 501,
    descripcion: 'Fumigación jardines',
    fechaInicio: new Date(2026, 2, 5, 8),
    fechaFin: new Date(2026, 2, 5, 12),
    grupoPlanId: null,
    periodoAnio: 2026,
    periodoMes: 3,
    conjuntoId: '9001',
    conjunto: { nombre: 'Conjunto Palmas' },
    operarios: [{ usuario: { nombre: 'Pedro' } }],
    herramientasPlanJson: [{ herramientaId: 1, cantidad: 5 }],
    usoHerramientas: [],
    ...overrides,
  };
}

function construirPrisma(overrides: Record<string, any> = {}) {
  const auditorias: any[] = [];

  const tx: any = {
    usoHerramienta: {
      create: jest.fn().mockResolvedValue({ id: 9001 }),
      delete: jest.fn().mockResolvedValue({}),
    },
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
    herramienta: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
    },
    conjuntoHerramientaStock: {
      findMany: jest.fn().mockResolvedValue([]),
      aggregate: jest.fn().mockResolvedValue({ _sum: { cantidad: 0 } }),
    },
    empresaHerramientaStock: {
      findMany: jest.fn().mockResolvedValue([]),
      aggregate: jest.fn().mockResolvedValue({ _sum: { cantidad: 0 } }),
    },
    usoHerramienta: {
      aggregate: jest.fn().mockResolvedValue({ _sum: { cantidad: 0 } }),
      findMany: jest.fn().mockResolvedValue([]),
      findUnique: jest.fn().mockResolvedValue(null),
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

describe('CronogramaHerramientaService', () => {
  describe('listarNecesidades', () => {
    test('PU-CH1 - agrupa por herramienta, conjunto y día sumando cantidades', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({ id: 501, herramientasPlanJson: [{ herramientaId: 1, cantidad: 2 }] }),
        tarea({
          id: 502,
          descripcion: 'Fumigación perímetro',
          herramientasPlanJson: [{ herramientaId: 1, cantidad: 1 }],
        }),
        // Otro dia: grupo distinto.
        tarea({
          id: 503,
          fechaInicio: new Date(2026, 2, 6, 8),
          fechaFin: new Date(2026, 2, 6, 10),
        }),
      ]);
      prisma.herramienta.findMany.mockResolvedValue([
        { id: 1, nombre: 'Fumigadora', unidad: 'UNIDAD', categoria: 'OTROS', modoControl: 'PRESTAMO' },
      ]);

      const service = new CronogramaHerramientaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({ anio: 2026, mes: 3 });

      expect(out.necesidades).toHaveLength(2);

      const dia5: any = out.necesidades.find((n: any) => n.fecha.getDate() === 5)!;
      expect(dia5.herramientaNombre).toBe('Fumigadora');
      expect(dia5.conjuntoNombre).toBe('Conjunto Palmas');
      expect(dia5.cantidadRequerida).toBe(3);
      expect(dia5.pendientes).toBe(3);
      expect(dia5.tareas.map((t: any) => t.tareaId)).toEqual([501, 502]);
    });

    test('PU-CH2 - descuenta lo ya asignado y expone capacidad de conjunto/empresa', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({
          herramientasPlanJson: [{ herramientaId: 1, cantidad: 5 }],
          usoHerramientas: [
            {
              id: 77,
              herramientaId: 1,
              cantidad: 2,
              origenStock: 'CONJUNTO',
              estado: 'RESERVADA',
              fechaInicio: new Date(2026, 2, 4),
              fechaFin: new Date(2026, 2, 7),
            },
          ],
        }),
      ]);
      prisma.herramienta.findMany.mockResolvedValue([
        { id: 1, nombre: 'Fumigadora', unidad: 'UNIDAD', categoria: 'OTROS', modoControl: 'PRESTAMO' },
      ]);
      prisma.conjuntoHerramientaStock.findMany.mockResolvedValue([
        { conjuntoId: '9001', herramientaId: 1, cantidad: 4 },
      ]);
      prisma.empresaHerramientaStock.findMany.mockResolvedValue([
        { herramientaId: 1, cantidad: 6 },
      ]);

      const service = new CronogramaHerramientaService(prisma, EMPRESA);
      const out: any = await service.listarNecesidades({ anio: 2026, mes: 3 });

      expect(out.necesidades[0].asignadas).toBe(2);
      expect(out.necesidades[0].pendientes).toBe(3);
      expect(out.necesidades[0].capacidadConjunto).toBe(4);
      expect(out.necesidades[0].capacidadEmpresa).toBe(6);
    });

    test('PU-CH3 - soloPendientes oculta las necesidades ya cubiertas', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({
          herramientasPlanJson: [{ herramientaId: 1, cantidad: 2 }],
          usoHerramientas: [
            {
              id: 77,
              herramientaId: 1,
              cantidad: 2,
              origenStock: 'CONJUNTO',
              estado: 'RESERVADA',
              fechaInicio: new Date(2026, 2, 4),
              fechaFin: new Date(2026, 2, 7),
            },
          ],
        }),
      ]);

      const service = new CronogramaHerramientaService(prisma, EMPRESA);
      const out = await service.listarNecesidades({
        anio: 2026,
        mes: 3,
        soloPendientes: true,
      });

      expect(out.necesidades).toHaveLength(0);
    });
  });

  describe('asignarHerramienta', () => {
    const fumigadora = { id: 1, nombre: 'Fumigadora', unidad: 'UNIDAD' };

    test('PU-CH4 - toma primero del conjunto y completa el resto con préstamo de empresa', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);
      prisma.conjuntoHerramientaStock.aggregate.mockResolvedValue({ _sum: { cantidad: 3 } });
      prisma.empresaHerramientaStock.aggregate.mockResolvedValue({ _sum: { cantidad: 10 } });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);
      const out: any = await service.asignarHerramienta({ tareaIds: [501], herramientaId: 1 });

      expect(out.ok).toBe(true);
      expect(out.tomarConjunto).toBe(3);
      expect(out.tomarEmpresa).toBe(2);
      expect(prisma.tx.usoHerramienta.create).toHaveBeenCalledTimes(2);

      const [conjuntoCall, empresaCall] = prisma.tx.usoHerramienta.create.mock.calls;
      expect(conjuntoCall[0].data.origenStock).toBe('CONJUNTO');
      expect(conjuntoCall[0].data.cantidad).toBe(3);
      expect(empresaCall[0].data.origenStock).toBe('EMPRESA');
      expect(empresaCall[0].data.cantidad).toBe(2);

      expect(prisma.auditorias[0]).toMatchObject({
        accion: 'ASIGNAR_HERRAMIENTA',
        actorId: 'ger-1',
        conjuntoId: '9001',
      });
    });

    test('PU-CH5 - no toca la empresa si el conjunto ya cubre todo', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);
      prisma.conjuntoHerramientaStock.aggregate.mockResolvedValue({ _sum: { cantidad: 5 } });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);
      const out: any = await service.asignarHerramienta({ tareaIds: [501], herramientaId: 1 });

      expect(out.tomarConjunto).toBe(5);
      expect(out.tomarEmpresa).toBe(0);
      expect(prisma.tx.usoHerramienta.create).toHaveBeenCalledTimes(1);
      expect(prisma.empresaHerramientaStock.aggregate).not.toHaveBeenCalled();
    });

    test('PU-CH6 - rechaza si ni el conjunto ni la empresa alcanzan', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);
      prisma.conjuntoHerramientaStock.aggregate.mockResolvedValue({ _sum: { cantidad: 1 } });
      prisma.empresaHerramientaStock.aggregate.mockResolvedValue({ _sum: { cantidad: 1 } });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarHerramienta({ tareaIds: [501], herramientaId: 1 }),
      ).rejects.toThrow(/no hay suficiente/i);
      expect(prisma.tx.usoHerramienta.create).not.toHaveBeenCalled();
    });

    test('PU-CH7 - no permite sobreasignar una necesidad ya cubierta', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);
      prisma.usoHerramienta.aggregate.mockResolvedValue({ _sum: { cantidad: 5 } });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarHerramienta({ tareaIds: [501], herramientaId: 1 }),
      ).rejects.toThrow(/completamente cubierta/i);
      expect(prisma.tx.usoHerramienta.create).not.toHaveBeenCalled();
    });

    test('PU-CH8 - rechaza herramientas que no requieren estas tareas', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea({ herramientasPlanJson: [] })]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarHerramienta({ tareaIds: [501], herramientaId: 1 }),
      ).rejects.toThrow(/no requieren/i);
    });

    test('PU-CH9 - no permite mezclar tareas de conjuntos distintos', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([
        tarea({ id: 501, conjuntoId: '9001' }),
        tarea({ id: 502, conjuntoId: '9002' }),
      ]);
      prisma.herramienta.findFirst.mockResolvedValue(fumigadora);

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarHerramienta({ tareaIds: [501, 502], herramientaId: 1 }),
      ).rejects.toThrow(/mismo conjunto/i);
    });

    test('PU-CH10 - rechaza herramienta que no pertenece a la empresa', async () => {
      const prisma = construirPrisma();
      prisma.tarea.findMany.mockResolvedValue([tarea()]);
      prisma.herramienta.findFirst.mockResolvedValue(null);

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.asignarHerramienta({ tareaIds: [501], herramientaId: 999 }),
      ).rejects.toThrow(/no existe para esta empresa/i);
    });
  });

  describe('liberarAsignacion', () => {
    test('PU-CH11 - borra el uso y audita', async () => {
      const prisma = construirPrisma();
      prisma.usoHerramienta.findUnique.mockResolvedValue({
        id: 9001,
        herramientaId: 1,
        cantidad: 3,
        origenStock: 'EMPRESA',
        herramienta: { nombre: 'Fumigadora' },
        tarea: {
          id: 501,
          descripcion: 'Fumigación jardines',
          conjuntoId: '9001',
          periodoAnio: 2026,
          periodoMes: 3,
        },
      });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);
      const out = await service.liberarAsignacion({ usoId: 9001 });

      expect(out).toEqual({ ok: true });
      expect(prisma.tx.usoHerramienta.delete).toHaveBeenCalledWith({ where: { id: 9001 } });
      expect(prisma.auditorias[0].accion).toBe('LIBERAR_HERRAMIENTA');
    });

    test('PU-CH12 - rechaza una asignación de otra empresa', async () => {
      const prisma = construirPrisma();
      prisma.usoHerramienta.findUnique.mockResolvedValue({
        id: 9001,
        herramientaId: 1,
        cantidad: 3,
        origenStock: 'CONJUNTO',
        herramienta: { nombre: 'Fumigadora' },
        tarea: { id: 501, descripcion: 'X', conjuntoId: 'AJENO' },
      });

      const service = new CronogramaHerramientaService(prisma, EMPRESA, ACTOR);

      await expect(
        service.liberarAsignacion({ usoId: 9001 }),
      ).rejects.toThrow(/no existe para esta empresa/i);
    });
  });
});
