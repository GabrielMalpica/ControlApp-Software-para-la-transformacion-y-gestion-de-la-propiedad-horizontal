import { CronogramaService } from "../../src/services/CronogramaServices";

describe("Informe jerárquico de cumplimiento", () => {
  const ocurrencias = [
    {
      id: "occ-1",
      conjuntoId: "C-1",
      periodoAnio: 2026,
      periodoMes: 8,
      borrador: true,
      defId: 10,
      descripcion: "Limpieza zona común",
      frecuencia: "SEMANAL",
      prioridad: 2,
      fechaObjetivo: new Date(2026, 7, 3),
      duracionEsperadaMin: 60,
      ubicacionId: 1,
      ubicacionNombre: "Torre A",
      elementoId: 2,
      elementoNombre: "Pasillo",
      operariosEsperadosIds: ["op-1"],
      operariosEsperadosNombres: ["Ana"],
      estado: "PROGRAMADA",
      motivoCodigo: null,
      motivoMensaje: null,
      fechaRealInicio: new Date(2026, 7, 3, 8),
      fechaRealFin: new Date(2026, 7, 3, 9),
    },
    {
      id: "occ-2",
      conjuntoId: "C-1",
      periodoAnio: 2026,
      periodoMes: 8,
      borrador: true,
      defId: 10,
      descripcion: "Limpieza zona común",
      frecuencia: "SEMANAL",
      prioridad: 2,
      fechaObjetivo: new Date(2026, 7, 5),
      duracionEsperadaMin: 60,
      ubicacionId: 1,
      ubicacionNombre: "Torre A",
      elementoId: 2,
      elementoNombre: "Pasillo",
      operariosEsperadosIds: ["op-2"],
      operariosEsperadosNombres: ["Luis"],
      estado: "SIN_PROGRAMAR",
      motivoCodigo: "SIN_HUECO",
      motivoMensaje: "No existe capacidad válida.",
      fechaRealInicio: null,
      fechaRealFin: null,
    },
    {
      id: "occ-fuera",
      conjuntoId: "C-1",
      periodoAnio: 2026,
      periodoMes: 8,
      borrador: true,
      defId: 10,
      descripcion: "Limpieza zona común",
      frecuencia: "SEMANAL",
      prioridad: 2,
      fechaObjetivo: new Date(2026, 7, 12),
      duracionEsperadaMin: 60,
      ubicacionId: 1,
      ubicacionNombre: "Torre A",
      elementoId: 2,
      elementoNombre: "Pasillo",
      operariosEsperadosIds: ["op-1"],
      operariosEsperadosNombres: ["Ana"],
      estado: "SIN_PROGRAMAR",
      motivoCodigo: "SIN_HUECO",
      motivoMensaje: null,
      fechaRealInicio: null,
      fechaRealFin: null,
    },
  ];

  function prismaMock() {
    return {
      preventivaOcurrenciaPlan: {
        findMany: jest.fn().mockResolvedValue(ocurrencias),
      },
      preventivaExcluidaBorrador: {
        findMany: jest.fn().mockResolvedValue([
          { ocurrenciaPlanId: "occ-2" },
          { ocurrenciaPlanId: "occ-fuera" },
        ]),
      },
      tarea: {
        findMany: jest.fn().mockImplementation(async ({ where }: any) =>
          where?.ocurrenciaPlanId === null
            ? []
            : [
                {
                  id: 100,
                  ocurrenciaPlanId: "occ-1",
                  fechaInicio: new Date(2026, 7, 3, 8),
                  fechaFin: new Date(2026, 7, 3, 9),
                  duracionMinutos: 60,
                  estado: "ASIGNADA",
                  operarios: [{ id: "op-1", usuario: { nombre: "Ana" } }],
                },
              ],
        ),
      },
    } as any;
  }

  test("incluye ocurrencias con cero horas y filtra la semana por fecha objetivo", async () => {
    const service = new CronogramaService(prismaMock(), "C-1");
    const out = await service.informeActividadJerarquico({
      anio: 2026,
      mes: 8,
      borrador: true,
      semanaInicio: "2026-08-03",
    });

    expect(out.resumen.esperadas).toBe(2);
    expect(out.resumen.conProgramacion).toBe(1);
    expect(out.resumen.sinProgramar).toBe(1);
    expect(out.ubicaciones[0].definiciones[0].ocurrencias).toHaveLength(2);
  });

  test("el filtro de operario conserva su ocurrencia esperada aunque tenga cero bloques", async () => {
    const service = new CronogramaService(prismaMock(), "C-1");
    const out = await service.informeActividadJerarquico({
      anio: 2026,
      mes: 8,
      borrador: true,
      semanaInicio: "2026-08-03",
      operarioId: "op-2",
    });

    expect(out.resumen.esperadas).toBe(1);
    expect(out.resumen.sinProgramar).toBe(1);
    expect(out.ubicaciones[0].definiciones[0].ocurrencias[0].id).toBe("occ-2");
    expect(out.ubicaciones[0].definiciones[0].ocurrencias[0].operariosEsperados)
      .toEqual([{ id: "op-2", nombre: "Luis" }]);
  });

  test("el filtro no conserva otros integrantes de una tarea compartida", async () => {
    const compartida = {
      ...ocurrencias[0],
      operariosEsperadosIds: ["op-1", "op-2"],
      operariosEsperadosNombres: ["Ana", "Luis"],
    };
    const prisma = prismaMock();
    prisma.preventivaOcurrenciaPlan.findMany.mockResolvedValue([compartida]);
    prisma.tarea.findMany.mockImplementation(async ({ where }: any) =>
      where?.ocurrenciaPlanId === null
        ? []
        : [{
            id: 100,
            ocurrenciaPlanId: "occ-1",
            fechaInicio: new Date(2026, 7, 3, 8),
            fechaFin: new Date(2026, 7, 3, 9),
            duracionMinutos: 60,
            estado: "ASIGNADA",
            operarios: [
              { id: "op-1", usuario: { nombre: "Ana" } },
              { id: "op-2", usuario: { nombre: "Luis" } },
            ],
          }],
    );
    const service = new CronogramaService(prisma, "C-1");

    const out = await service.informeActividadJerarquico({
      anio: 2026,
      mes: 8,
      borrador: true,
      operarioId: "op-1",
    });
    const ocurrencia = out.ubicaciones[0].definiciones[0].ocurrencias[0];

    expect(ocurrencia.operariosEsperados).toEqual([
      { id: "op-1", nombre: "Ana" },
    ]);
    expect(ocurrencia.bloques[0].operarios).toEqual([
      { id: "op-1", nombre: "Ana" },
    ]);
  });

  test("ignora trazabilidad huerfana de cronogramas eliminados anteriormente", async () => {
    const huerfana = {
      ...ocurrencias[0],
      id: "occ-antigua",
      fechaRealInicio: new Date(2026, 7, 4, 8),
      fechaRealFin: new Date(2026, 7, 4, 9),
    };
    const prisma = prismaMock();
    prisma.preventivaOcurrenciaPlan.findMany.mockResolvedValue([
      ocurrencias[0],
      huerfana,
    ]);
    prisma.preventivaExcluidaBorrador.findMany.mockResolvedValue([]);
    const service = new CronogramaService(prisma, "C-1");

    const out = await service.informeActividadJerarquico({
      anio: 2026,
      mes: 8,
      borrador: true,
    });

    expect(out.resumen.esperadas).toBe(1);
    expect(out.resumen.conProgramacion).toBe(1);
    expect(out.resumen.completas).toBe(1);
    expect(out.resumen.sinProgramar).toBe(0);
  });
});
