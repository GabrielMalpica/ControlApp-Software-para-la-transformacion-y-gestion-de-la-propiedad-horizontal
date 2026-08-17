import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

describe("Regeneración atómica del borrador", () => {
  test("si la reconstrucción falla después de borrar, la transacción conserva el borrador anterior", async () => {
    let tareas = [{ id: 1, descripcion: "Borrador existente" }];
    const queryRaw = jest.fn().mockResolvedValue([]);
    const tx: any = {
      $queryRaw: queryRaw,
      tarea: {
        deleteMany: jest.fn().mockImplementation(async () => {
          const count = tareas.length;
          tareas = [];
          return { count };
        }),
      },
    };
    const prisma: any = {
      $transaction: jest.fn().mockImplementation(async (callback: any) => {
        const snapshot = [...tareas];
        try {
          return await callback(tx);
        } catch (error) {
          tareas = snapshot;
          throw error;
        }
      }),
    };
    const generation = jest
      .spyOn(
        DefinicionTareaPreventivaService.prototype,
        "generarBorradorMensual",
      )
      .mockImplementation(async function (
        this: DefinicionTareaPreventivaService,
      ) {
        await (this as any).prisma.tarea.deleteMany({});
        throw new Error("Fallo simulado durante la reconstrucción");
      });

    const service = new DefinicionTareaPreventivaService(prisma);
    await expect(
      service.generarCronograma({
        conjuntoId: "C-100",
        anio: 2026,
        mes: 8,
        modo: "RESET",
      }),
    ).rejects.toThrow("Fallo simulado");

    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(queryRaw).toHaveBeenCalledTimes(1);
    expect(tareas).toEqual([{ id: 1, descripcion: "Borrador existente" }]);
    generation.mockRestore();
  });
});
