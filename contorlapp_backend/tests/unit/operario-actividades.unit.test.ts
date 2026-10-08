import { OperarioService } from '../../src/services/OperarioServices';
import { limpiarIconoCategoria } from '../../src/utils/categoriaIconos';
import { adjuntarCategoriaCronograma } from '../../src/utils/categoriaCronograma';

type TareaFake = {
  id: number;
  borrador: boolean;
  estado: string;
  operarios: Array<{ id: string }>;
};

function prismaConTarea(tarea: TareaFake | null) {
  return {
    tarea: {
      findUnique: jest.fn(async () => tarea),
      update: jest.fn(async ({ data }: any) => ({ ...tarea, ...data })),
    },
  } as any;
}

describe('iniciar actividad (operario)', () => {
  test('el operario asignado la pasa a EN_PROCESO con hora de inicio', async () => {
    const prisma = prismaConTarea({
      id: 5,
      borrador: false,
      estado: 'ASIGNADA',
      operarios: [{ id: '100' }, { id: '200' }],
    });
    await new OperarioService(prisma, 200).iniciarTarea({ tareaId: 5 });

    expect(prisma.tarea.update).toHaveBeenCalledTimes(1);
    const data = prisma.tarea.update.mock.calls[0][0].data;
    expect(data.estado).toBe('EN_PROCESO');
    expect(data.fechaIniciarTarea).toBeInstanceOf(Date);
  });

  test('rechaza una tarea que no es del operario (403) sin modificarla', async () => {
    const prisma = prismaConTarea({
      id: 5,
      borrador: false,
      estado: 'ASIGNADA',
      operarios: [{ id: '100' }],
    });
    await expect(new OperarioService(prisma, 999).iniciarTarea({ tareaId: 5 })).rejects.toMatchObject({
      status: 403,
    });
    expect(prisma.tarea.update).not.toHaveBeenCalled();
  });

  test('rechaza borradores e inexistentes (404)', async () => {
    const borrador = prismaConTarea({ id: 5, borrador: true, estado: 'ASIGNADA', operarios: [{ id: '1' }] });
    await expect(new OperarioService(borrador, 1).iniciarTarea({ tareaId: 5 })).rejects.toMatchObject({
      status: 404,
    });
    await expect(new OperarioService(prismaConTarea(null), 1).iniciarTarea({ tareaId: 5 })).rejects.toMatchObject({
      status: 404,
    });
  });

  test('no reinicia una actividad ya iniciada o cerrada (409)', async () => {
    const prisma = prismaConTarea({ id: 5, borrador: false, estado: 'EN_PROCESO', operarios: [{ id: '1' }] });
    await expect(new OperarioService(prisma, 1).iniciarTarea({ tareaId: 5 })).rejects.toMatchObject({
      status: 409,
    });
    expect(prisma.tarea.update).not.toHaveBeenCalled();
  });
});

describe('lista de actividades del operario', () => {
  function prismaLista() {
    return {
      tarea: {
        findMany: jest.fn(async () => [
          {
            id: 1,
            categoriaId: 4,
            definicionId: null,
            finalizadaPorId: '200',
            operarios: [
              { id: '100', funciones: ['ASEO'], usuario: { nombre: 'María Gómez' } },
              { id: '200', funciones: ['TODERO'], usuario: { nombre: 'Juan Pérez' } },
            ],
          },
          { id: 2, categoriaId: null, definicionId: null, finalizadaPorId: null, operarios: [] },
        ]),
      },
      definicionTareaPreventiva: { findMany: jest.fn(async () => []) },
      categoriaTarea: {
        findMany: jest.fn(async () => [{ id: 4, nombre: 'Aseo', colorHex: '#1f6fb2', icono: 'limpieza' }]),
      },
      usuario: { findMany: jest.fn(async () => [{ id: '200', nombre: 'Juan Pérez' }]) },
    } as any;
  }

  test('limita por rango e incluye compañeros, categoría y quién la cerró', async () => {
    const prisma = prismaLista();
    const desde = new Date('2026-10-01T05:00:00.000Z');
    const hasta = new Date('2026-11-01T05:00:00.000Z');
    const lista = await new OperarioService(prisma, 100).listarTareas({ desde, hasta });

    const where = prisma.tarea.findMany.mock.calls[0][0].where;
    expect(where.fechaInicio).toEqual({ gte: desde, lte: hasta });
    expect(where.operarios).toEqual({ some: { id: '100' } });
    expect(prisma.tarea.findMany.mock.calls[0][0].include.operarios).toBeDefined();

    expect(lista[0]).toMatchObject({
      categoriaNombre: 'Aseo',
      categoriaColorHex: '#1F6FB2',
      categoriaIcono: 'limpieza',
      finalizadaPorNombre: 'Juan Pérez',
    });
    expect(lista[1]).toMatchObject({ categoriaNombre: null, finalizadaPorNombre: null });
  });

  test('sin rango no filtra por fecha (compatibilidad con la app anterior)', async () => {
    const prisma = prismaLista();
    await new OperarioService(prisma, 100).listarTareas();
    expect(prisma.tarea.findMany.mock.calls[0][0].where.fechaInicio).toBeUndefined();
  });
});

describe('ícono de categoría', () => {
  test('acepta claves conocidas y vacío como "sin ícono"', () => {
    expect(limpiarIconoCategoria('piscina')).toBe('piscina');
    expect(limpiarIconoCategoria('  limpieza ')).toBe('limpieza');
    expect(limpiarIconoCategoria('')).toBeNull();
    expect(limpiarIconoCategoria(null)).toBeNull();
    expect(limpiarIconoCategoria(undefined)).toBeNull();
  });

  test('rechaza claves desconocidas con 400', () => {
    expect(() => limpiarIconoCategoria('cohete')).toThrow(expect.objectContaining({ status: 400 }));
  });

  test('el cronograma recibe el ícono solo si es válido', async () => {
    const prisma = {
      definicionTareaPreventiva: { findMany: jest.fn(async () => []) },
      categoriaTarea: {
        findMany: jest.fn(async () => [
          { id: 1, nombre: 'Piscinas', colorHex: '#B8520A', icono: 'piscina' },
          { id: 2, nombre: 'Rara', colorHex: '#4B5563', icono: 'icono-borrado' },
        ]),
      },
    } as any;
    const r = await adjuntarCategoriaCronograma(prisma, [
      { categoriaId: 1, definicionId: null },
      { categoriaId: 2, definicionId: null },
    ]);
    expect(r[0].categoriaIcono).toBe('piscina');
    expect(r[1].categoriaIcono).toBeNull();
  });
});
