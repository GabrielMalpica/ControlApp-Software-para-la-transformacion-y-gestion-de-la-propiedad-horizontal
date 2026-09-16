import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

function makeFakePrisma() {
  const necesidadesSeed = [
    { id: 501, conjuntoId: "C-1" },
    { id: 502, conjuntoId: "C-1" },
    { id: 999, conjuntoId: "OTRO-CONJUNTO" },
  ];
  const creadas: any[] = [];
  const definicionesSeed = new Map<number, any>([
    [10, { id: 10, conjuntoId: "C-1", necesidades: [] }],
  ]);

  const prisma: any = {
    conjuntoNecesidadOperario: {
      findMany: jest.fn(async ({ where }: any) => {
        const ids: number[] = where.id?.in ?? [];
        return necesidadesSeed.filter(
          (n) => ids.includes(n.id) && n.conjuntoId === where.conjuntoId,
        );
      }),
    },
    definicionTareaPreventiva: {
      create: jest.fn(async ({ data }: any) => {
        const creada = { id: 100 + creadas.length, ...data };
        creadas.push(creada);
        return creada;
      }),
      findUnique: jest.fn(async ({ where }: any) => definicionesSeed.get(where.id) ?? null),
      update: jest.fn(async ({ where, data }: any) => ({ id: where.id, ...data })),
    },
  };

  return { prisma, creadas };
}

describe("DefinicionTareaPreventivaService: necesidadesIds", () => {
  test("crear() conecta las necesidades cuando pertenecen al conjunto", async () => {
    const { prisma, creadas } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.crear({
      conjuntoId: "C-1",
      ubicacionId: 1,
      elementoId: 2,
      descripcion: "Ronda salvavidas",
      frecuencia: "DIARIA",
      duracionMinutosFija: 60,
      necesidadesIds: [501, 502],
    });

    expect(creadas).toHaveLength(1);
    expect(creadas[0].necesidades).toEqual({
      connect: [{ id: 501 }, { id: 502 }],
    });
  });

  test("crear() rechaza una necesidad que pertenece a otro conjunto", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    await expect(
      service.crear({
        conjuntoId: "C-1",
        ubicacionId: 1,
        elementoId: 2,
        descripcion: "Ronda salvavidas",
        frecuencia: "DIARIA",
        duracionMinutosFija: 60,
        necesidadesIds: [999],
      }),
    ).rejects.toThrow(/no pertenece a este conjunto/);
  });

  test("actualizar() con necesidadesIds:[] libera todas las necesidades vinculadas", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    const actualizada: any = await service.actualizar("C-1", 10, { necesidadesIds: [] });

    expect(actualizada.necesidades).toEqual({ set: [] });
  });

  test("actualizar() con necesidadesIds reemplaza el vínculo completo (set)", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    const actualizada: any = await service.actualizar("C-1", 10, { necesidadesIds: [501] });

    expect(actualizada.necesidades).toEqual({ set: [{ id: 501 }] });
  });
});
