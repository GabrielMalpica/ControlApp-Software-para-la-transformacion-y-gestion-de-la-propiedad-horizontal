import { adjuntarCategoriaCronograma } from '../../src/utils/categoriaCronograma';

function construirPrisma() {
  return {
    definicionTareaPreventiva: {
      findMany: jest.fn(async ({ where }: any) =>
        [{ id: 10, categoriaId: 4 }].filter((d) => where.id.in.includes(d.id)),
      ),
    },
    categoriaTarea: {
      findMany: jest.fn(async ({ where }: any) =>
        [
          { id: 4, nombre: 'Aseo', colorHex: '#8e24aa' },
          { id: 7, nombre: 'Supervisión', colorHex: 'sin-color' },
        ].filter((c) => where.id.in.includes(c.id)),
      ),
    },
  } as any;
}

describe('color de categoria en el cronograma', () => {
  test('usa la categoria de la tarea y, si no tiene, la de su preventiva', async () => {
    const prisma = construirPrisma();
    const resultado = await adjuntarCategoriaCronograma(prisma, [
      { id: 1, categoriaId: 4, definicionId: null },
      { id: 2, categoriaId: null, definicionId: 10 }, // tarea dividida: no copió la categoria
      { id: 3, categoriaId: null, definicionId: 99 }, // sin categoria
    ]);

    expect(resultado[0]).toMatchObject({
      categoriaId: 4,
      categoriaNombre: 'Aseo',
      categoriaColorHex: '#8E24AA',
    });
    expect(resultado[1]).toMatchObject({ categoriaId: 4, categoriaColorHex: '#8E24AA' });
    expect(resultado[2]).toMatchObject({
      categoriaId: null,
      categoriaNombre: null,
      categoriaColorHex: null,
    });
    // Solo consulta las definiciones de las tareas sin categoria propia.
    expect(prisma.definicionTareaPreventiva.findMany.mock.calls[0][0].where.id.in).toEqual([
      10, 99,
    ]);
  });

  test('un color invalido no se envia al cliente', async () => {
    const resultado = await adjuntarCategoriaCronograma(construirPrisma(), [
      { categoriaId: 7, definicionId: null },
    ]);
    expect(resultado[0]).toMatchObject({ categoriaNombre: 'Supervisión', categoriaColorHex: null });
  });

  test('sin tareas no consulta nada', async () => {
    const prisma = construirPrisma();
    expect(await adjuntarCategoriaCronograma(prisma, [])).toEqual([]);
    expect(prisma.categoriaTarea.findMany).not.toHaveBeenCalled();
  });
});
