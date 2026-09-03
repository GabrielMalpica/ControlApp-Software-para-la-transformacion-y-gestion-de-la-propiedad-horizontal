import { CronogramaService } from "../../src/services/CronogramaServices";

describe("Eliminacion de cronograma publicado", () => {
  const conjuntoId = "860506140-6";
  const actor = { id: "gerente-1", rol: "gerente", nombre: "Gerente" };

  function crearPrisma(tareas: Array<{ id: number; estado: string }>) {
    const tareaUpdate = jest.fn();
    const tx = {
      maquinariaConjunto: {
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      usoMaquinaria: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      usoHerramienta: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      consumoInsumo: {
        deleteMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
      tarea: {
        update: tareaUpdate,
        deleteMany: jest.fn().mockResolvedValue({ count: tareas.length }),
      },
    };

    const prisma = {
      tarea: {
        findMany: jest.fn().mockResolvedValue(
          tareas.map((tarea) => ({
            ...tarea,
            periodoAnio: 2026,
            periodoMes: 9,
          })),
        ),
        count: jest.fn().mockResolvedValue(0),
      },
      auditoriaEvento: {
        create: jest.fn().mockResolvedValue({}),
      },
      $transaction: jest.fn(async (callback: (client: typeof tx) => unknown) =>
        callback(tx),
      ),
    };

    return { prisma, tx, tareaUpdate };
  }

  test("borra un cronograma grande con una cantidad constante de consultas", async () => {
    const tareas = Array.from({ length: 600 }, (_, index) => ({
      id: index + 1,
      estado: "ASIGNADA",
    }));
    const { prisma, tx, tareaUpdate } = crearPrisma(tareas);
    const service = new CronogramaService(prisma as any, conjuntoId, actor);

    await expect(
      service.eliminarCronogramaPublicado({ anio: 2026, mes: 9 }),
    ).resolves.toEqual({ ok: true, eliminadas: 600 });

    const ids = tareas.map((tarea) => tarea.id);
    expect(prisma.$transaction).toHaveBeenCalledTimes(1);
    expect(tx.maquinariaConjunto.updateMany).toHaveBeenCalledWith({
      where: { tareaId: { in: ids } },
      data: { tareaId: null },
    });
    expect(tx.usoMaquinaria.deleteMany).toHaveBeenCalledTimes(1);
    expect(tx.usoHerramienta.deleteMany).toHaveBeenCalledTimes(1);
    expect(tx.consumoInsumo.deleteMany).toHaveBeenCalledTimes(1);
    expect(tareaUpdate).not.toHaveBeenCalled();
    expect(tx.tarea.deleteMany).toHaveBeenCalledWith({
      where: { id: { in: ids } },
    });
    expect(prisma.auditoriaEvento.create).toHaveBeenCalledTimes(1);
  });

  test("no borra nada cuando existe una tarea ejecutada", async () => {
    const { prisma, tx } = crearPrisma([
      { id: 1, estado: "ASIGNADA" },
      { id: 2, estado: "APROBADA" },
    ]);
    const service = new CronogramaService(prisma as any, conjuntoId, actor);

    await expect(
      service.eliminarCronogramaPublicado({ anio: 2026, mes: 9 }),
    ).rejects.toThrow(
      "No se puede eliminar el cronograma porque tiene tareas completadas o pendientes de aprobacion.",
    );

    expect(prisma.$transaction).not.toHaveBeenCalled();
    expect(tx.tarea.deleteMany).not.toHaveBeenCalled();
    expect(prisma.auditoriaEvento.create).not.toHaveBeenCalled();
  });
});
