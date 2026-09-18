import { DiaSemana } from "@prisma/client";
import { DefinicionTareaPreventivaService } from "../../src/services/DefinicionTareaPreventivaService";

function makeFakePrisma() {
  const necesidadesSeed = [
    { id: 501, conjuntoId: "C-1", etiqueta: "Todero #1", horarioEspecial: false, horarios: [] as { dia: DiaSemana }[] },
    {
      id: 502,
      conjuntoId: "C-1",
      etiqueta: "Salvavidas #1",
      horarioEspecial: true,
      horarios: [{ dia: DiaSemana.DOMINGO }],
    },
    { id: 999, conjuntoId: "OTRO-CONJUNTO", etiqueta: "Otro", horarioEspecial: false, horarios: [] },
  ];
  // Horario general de C-1: lunes a viernes (sin fin de semana).
  const horarioGeneralSeed = [
    DiaSemana.LUNES,
    DiaSemana.MARTES,
    DiaSemana.MIERCOLES,
    DiaSemana.JUEVES,
    DiaSemana.VIERNES,
  ].map((dia) => ({ dia }));
  const creadas: any[] = [];
  const definicionesSeed = new Map<number, any>([
    [10, { id: 10, conjuntoId: "C-1", necesidades: [] }],
    [
      20,
      {
        id: 20,
        conjuntoId: "C-1",
        frecuencia: "SEMANAL",
        diaSemanaProgramado: DiaSemana.MARTES,
        necesidades: [],
      },
    ],
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
    conjuntoHorario: {
      findMany: jest.fn(async () => horarioGeneralSeed),
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

describe("DefinicionTareaPreventivaService: compatibilidad día programado vs horario de la necesidad", () => {
  test("crear() rechaza un día SEMANAL que la plaza (sin horario especial) no trabaja según el horario general", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    // Todero #1 (501) hereda el horario general L-V; domingo no está cubierto.
    await expect(
      service.crear({
        conjuntoId: "C-1",
        ubicacionId: 1,
        elementoId: 2,
        descripcion: "Ronda todero",
        frecuencia: "SEMANAL",
        diaSemanaProgramado: "DOMINGO",
        duracionMinutosFija: 60,
        necesidadesIds: [501],
      }),
    ).rejects.toThrow(/está fuera del horario/);
  });

  test("crear() rechaza un día SEMANAL fuera del horario especial de la plaza", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    // Salvavidas #1 (502) solo tiene horario especial el domingo.
    await expect(
      service.crear({
        conjuntoId: "C-1",
        ubicacionId: 1,
        elementoId: 2,
        descripcion: "Cuidado piscina",
        frecuencia: "SEMANAL",
        diaSemanaProgramado: "MARTES",
        duracionMinutosFija: 60,
        necesidadesIds: [502],
      }),
    ).rejects.toThrow(/está fuera del horario/);
  });

  test("crear() acepta un día SEMANAL que sí coincide con el horario especial de la plaza", async () => {
    const { prisma, creadas } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    await service.crear({
      conjuntoId: "C-1",
      ubicacionId: 1,
      elementoId: 2,
      descripcion: "Cuidado piscina",
      frecuencia: "SEMANAL",
      diaSemanaProgramado: "DOMINGO",
      duracionMinutosFija: 60,
      necesidadesIds: [502],
    });

    expect(creadas).toHaveLength(1);
  });

  test("crear() con frecuencia MENSUAL no valida el día (el día de semana varía cada mes)", async () => {
    const { prisma, creadas } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    // Salvavidas #1 (502) solo trabaja domingo, pero MENSUAL usa día-del-mes.
    await service.crear({
      conjuntoId: "C-1",
      ubicacionId: 1,
      elementoId: 2,
      descripcion: "Revisión mensual",
      frecuencia: "MENSUAL",
      diaMesProgramado: 15,
      duracionMinutosFija: 60,
      necesidadesIds: [502],
    });

    expect(creadas).toHaveLength(1);
  });

  test("actualizar() rechaza vincular una necesidad cuando el día YA guardado (no tocado en este payload) no coincide con su horario especial", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    // Definición 20 ya tiene SEMANAL/MARTES guardado; solo se le agrega la
    // necesidad 502 (que únicamente trabaja domingo) en este payload.
    await expect(
      service.actualizar("C-1", 20, { necesidadesIds: [502] }),
    ).rejects.toThrow(/está fuera del horario/);
  });

  test("actualizar() acepta cambiar el día programado a uno cubierto por la necesidad ya vinculada", async () => {
    const { prisma } = makeFakePrisma();
    const service = new DefinicionTareaPreventivaService(prisma);

    const actualizada: any = await service.actualizar("C-1", 20, {
      necesidadesIds: [502],
      diaSemanaProgramado: "DOMINGO",
    });

    expect(actualizada.necesidades).toEqual({ set: [{ id: 502 }] });
  });
});
