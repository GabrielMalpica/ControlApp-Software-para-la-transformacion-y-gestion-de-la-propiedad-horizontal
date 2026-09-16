import { GerenteService } from "../../src/services/GerenteServices";

function makeFakePrisma() {
  // "1" a propósito: GerenteService.editarOperario recibe operarioId numérico
  // y hace operarioId.toString() antes de tocar Prisma; se usa el mismo id
  // en ambos flujos (traslado y edición) para poder compartir el fixture.
  const necesidades = new Map<number, { id: number; operarioId: string | null; activo: boolean; rol: string; etiqueta: string }>([
    [501, { id: 501, operarioId: "1", activo: true, rol: "TODERO", etiqueta: "Todero #1" }],
  ]);
  const operarioUpdates: any[] = [];

  const prisma: any = {
    empresa: {
      findUnique: jest.fn().mockResolvedValue({ nit: "EMP-1" }),
    },
    operario: {
      findFirst: jest.fn().mockResolvedValue({
        id: "1",
        conjuntos: [{ nit: "C-ORIGEN" }],
      }),
      update: jest.fn(async ({ where, data }: any) => {
        operarioUpdates.push({ where, data });
        return { id: where.id };
      }),
    },
    conjunto: {
      findFirst: jest.fn().mockResolvedValue({ nit: "C-DESTINO" }),
    },
    tarea: {
      count: jest.fn().mockResolvedValue(0),
    },
    conjuntoNecesidadOperario: {
      updateMany: jest.fn(async ({ where, data }: any) => {
        let count = 0;
        for (const n of necesidades.values()) {
          if (n.operarioId === where.operarioId && (where.activo == null || n.activo === where.activo)) {
            n.operarioId = data.operarioId;
            count++;
          }
        }
        return { count };
      }),
      findFirst: jest.fn(async ({ where }: any) => {
        for (const n of necesidades.values()) {
          if (
            n.operarioId === where.operarioId &&
            n.activo === where.activo &&
            !where.rol.notIn.includes(n.rol)
          ) {
            return { etiqueta: n.etiqueta, rol: n.rol };
          }
        }
        return null;
      }),
    },
    $transaction: async (fn: any) => fn(prisma),
    usuario: { update: jest.fn().mockResolvedValue({}) },
  };

  return { prisma, necesidades, operarioUpdates };
}

describe("GerenteService: necesidades operativas al trasladar/editar un operario", () => {
  test("trasladarOperario libera cualquier plaza que el operario ocupaba", async () => {
    const { prisma, necesidades } = makeFakePrisma();
    const service = new GerenteService(prisma, "EMP-1");

    const result = await service.trasladarOperario("1", { conjuntoId: "C-DESTINO" });

    expect(result).toEqual({ ok: true });
    expect(necesidades.get(501)?.operarioId).toBeNull();
    expect(prisma.conjuntoNecesidadOperario.updateMany).toHaveBeenCalledWith({
      where: { operarioId: "1", activo: true },
      data: { operarioId: null },
    });
  });

  test("editarOperario rechaza quitar un rol que una plaza ocupada exige", async () => {
    const { prisma } = makeFakePrisma();
    const service = new GerenteService(prisma, "EMP-1");

    // op-1 ocupa Todero #1 (rol TODERO); intenta quedarse solo con SALVAVIDAS.
    await expect(
      service.editarOperario(1 as any, { funciones: ["SALVAVIDAS"] }),
    ).rejects.toThrow(/Todero #1/);
  });

  test("editarOperario permite el cambio si el rol de la plaza se conserva", async () => {
    const { prisma } = makeFakePrisma();
    const service = new GerenteService(prisma, "EMP-1");

    await service.editarOperario(1 as any, { funciones: ["TODERO", "SALVAVIDAS"] });

    expect(prisma.operario.update).toHaveBeenCalledWith({
      where: { id: "1" },
      data: { funciones: ["TODERO", "SALVAVIDAS"] },
    });
  });
});
