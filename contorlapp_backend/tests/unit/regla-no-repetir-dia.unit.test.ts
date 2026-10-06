import { DefinicionTareaPreventivaService } from '../../src/services/DefinicionTareaPreventivaService';

function servicioConExistentes(existentes: any[]) {
  const prisma: any = {
    tarea: { findMany: jest.fn().mockResolvedValue(existentes) },
  };
  return {
    prisma,
    service: new DefinicionTareaPreventivaService(prisma) as any,
  };
}

const identidad = {
  definicionId: 347,
  descripcion: 'Realizar barrido y limpieza general',
  ubicacionId: 230,
  elementoId: 992,
  ocurrenciaPlanId: 'OCC-A',
};

describe('regla: la misma tarea no se repite el mismo dia', () => {
  const fecha = new Date(2026, 7, 15, 9);

  test('rechaza si otra ocurrencia (aunque sea de otra definicion con la misma firma) ya esta ese dia', async () => {
    const { service, prisma } = servicioConExistentes([
      { id: 1, ocurrenciaPlanId: 'OCC-B', grupoPlanId: null },
    ]);

    await expect(
      service.validarNoRepiteDefinicionEnDia({ conjuntoId: '9001', fecha, identidad }),
    ).rejects.toThrow(/no se repite dos veces el mismo día/);

    // La consulta cubre la definicion Y la misma descripcion+ubicacion+elemento
    // sin exigir que la otra tarea carezca de definicion.
    const where = prisma.tarea.findMany.mock.calls[0][0].where;
    expect(where.OR).toEqual([
      { definicionId: 347 },
      {
        descripcion: { equals: 'Realizar barrido y limpieza general', mode: 'insensitive' },
        ubicacionId: 230,
        elementoId: 992,
      },
    ]);
  });

  test('permite los demas bloques de la misma ocurrencia o grupo', async () => {
    const { service } = servicioConExistentes([
      { id: 1, ocurrenciaPlanId: 'OCC-A', grupoPlanId: null },
      { id: 2, ocurrenciaPlanId: null, grupoPlanId: 'OCC-A' },
    ]);

    await expect(
      service.validarNoRepiteDefinicionEnDia({ conjuntoId: '9001', fecha, identidad }),
    ).resolves.toBeUndefined();
  });

  test('sin tareas ese dia no bloquea', async () => {
    const { service } = servicioConExistentes([]);
    await expect(
      service.validarNoRepiteDefinicionEnDia({ conjuntoId: '9001', fecha, identidad }),
    ).resolves.toBeUndefined();
  });

  test('el cache del generador tambien detecta la misma firma en otra definicion', () => {
    const { service } = servicioConExistentes([]);
    const base = {
      descripcion: 'Realizar barrido y limpieza general',
      ubicacionId: 230,
      elementoId: 992,
    };
    service.firmaPorDefinicionScheduler.set(347, 'realizar barrido y limpieza general|230|992');
    service.firmaPorDefinicionScheduler.set(348, 'realizar barrido y limpieza general|230|992');

    service.registrarOcurrenciaDefinicionDiaScheduler({
      definicionId: 347,
      ocurrenciaPlanId: 'OCC-A',
      bloques: [{ fechaInicio: fecha, fechaFin: new Date(2026, 7, 15, 10) }],
    });

    // Otra definicion con la misma firma ya no puede usar ese dia...
    expect(
      service.hayOtraOcurrenciaDefinicionEnDia({
        definicionId: 348,
        ocurrenciaPlanId: 'OCC-B',
        fecha,
      }),
    ).toBe(true);
    // ...pero la propia ocurrencia si, y otro dia queda libre.
    expect(
      service.hayOtraOcurrenciaDefinicionEnDia({
        definicionId: 347,
        ocurrenciaPlanId: 'OCC-A',
        fecha,
      }),
    ).toBe(false);
    expect(
      service.hayOtraOcurrenciaDefinicionEnDia({
        definicionId: 348,
        ocurrenciaPlanId: 'OCC-B',
        fecha: new Date(2026, 7, 16),
      }),
    ).toBe(false);
    expect(base.ubicacionId).toBe(230);
  });
});
