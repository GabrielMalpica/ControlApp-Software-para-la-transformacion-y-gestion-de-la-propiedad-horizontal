import { AsistenciaService } from "../../src/services/AsistenciaService";

/**
 * Prisma falso acotado a lo que usa AsistenciaService.checkin: conjunto,
 * operario, conceptos, festivos (guardados a medianoche LOCAL, igual que
 * EmpresaServices.reemplazarFestivosEnRango) y la plaza (necesidad
 * operativa) del operario, si tiene una.
 */
function construirPrisma(opts: {
  festivos?: Array<{ fecha: Date; nombre?: string | null }>;
  necesidad?: { descansoCompensatorio: boolean } | null;
}) {
  const CONCEPTOS = [
    { id: 1, empresaId: "EMP-1", codigo: "A", nombre: "Asistencia" },
    { id: 2, empresaId: "EMP-1", codigo: "DFC", nombre: "Domingo/festivo con compensatorio" },
    { id: 3, empresaId: "EMP-1", codigo: "DFP", nombre: "Domingo/festivo pleno" },
  ];
  const registros = new Map<string, any>();
  let secuencia = 100;

  const prisma: any = {
    conjunto: {
      findUnique: jest.fn().mockResolvedValue({
        nit: "C-1",
        nombre: "Conjunto Uno",
        qrAsistenciaToken: "tok-1",
      }),
    },
    operario: {
      findUnique: jest.fn().mockResolvedValue({ id: "op-1", empresaId: "EMP-1" }),
    },
    conceptoAsistencia: {
      count: jest.fn().mockResolvedValue(CONCEPTOS.length),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
      findUnique: jest.fn(async ({ where }: any) => {
        const codigo = where.empresaId_codigo.codigo;
        return CONCEPTOS.find((c) => c.codigo === codigo) ?? null;
      }),
    },
    festivo: {
      findFirst: jest.fn(async ({ where }: any) => {
        const gte: Date = where.fecha.gte;
        const lt: Date = where.fecha.lt;
        const match = (opts.festivos ?? []).find((f) => f.fecha >= gte && f.fecha < lt);
        return match ? { fecha: match.fecha, nombre: match.nombre ?? null } : null;
      }),
    },
    // Conjunto L-V (sábado y domingo no tienen horario = día de descanso).
    conjuntoHorario: {
      findUnique: jest.fn(async ({ where }: any) =>
        ["LUNES", "MARTES", "MIERCOLES", "JUEVES", "VIERNES"].includes(where.conjuntoId_dia.dia)
          ? { horaApertura: "07:00", horaCierre: "16:00", descansoInicio: null, descansoFin: null }
          : null,
      ),
    },
    conjuntoNecesidadOperario: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(
        opts.necesidad
          ? { descansoCompensatorio: opts.necesidad.descansoCompensatorio }
          : null,
      ),
    },
    registroAsistencia: {
      findUnique: jest.fn(async ({ where }: any) => {
        const key = `${where.operarioId_fecha.operarioId}|${where.operarioId_fecha.fecha.toISOString()}`;
        return registros.get(key) ?? null;
      }),
      create: jest.fn(async ({ data }: any) => {
        const id = ++secuencia;
        const concepto = CONCEPTOS.find((c) => c.id === data.conceptoId)!;
        const creado = { id, ...data, concepto };
        registros.set(`${data.operarioId}|${data.fecha.toISOString()}`, creado);
        return creado;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const entry = Array.from(registros.values()).find((r) => r.id === where.id);
        Object.assign(entry, data);
        return entry;
      }),
    },
  };

  return { prisma, registros };
}

// Fechas a medianoche LOCAL (igual que Festivo.fecha en BD).
const SABADO_FESTIVO = new Date(2026, 3, 4); // día de descanso del conjunto L-V
const MIERCOLES_FESTIVO = new Date(2026, 3, 1); // día que sí se trabaja

const QR = "CTRLAPP-ASISTENCIA|C-1|tok-1";
const checkin = (service: AsistenciaService) =>
  service.checkin({ operarioId: "op-1", conjuntoId: "C-1", qrPayload: QR });

describe("AsistenciaService.checkin - festivos y día de descanso", () => {
  function congelarFecha(fecha: Date) {
    jest.useFakeTimers({ now: fecha, doNotFake: ["nextTick", "setImmediate"] });
  }
  afterEach(() => {
    jest.useRealTimers();
  });

  test("detecta el festivo aunque Festivo.fecha esté a medianoche local (bug corregido: antes comparaba contra UTC)", async () => {
    congelarFecha(new Date(2026, 3, 4, 10, 0, 0));
    const { prisma } = construirPrisma({
      festivos: [{ fecha: SABADO_FESTIVO, nombre: "Festivo de prueba" }],
      necesidad: { descansoCompensatorio: true },
    });
    const resultado = await checkin(new AsistenciaService(prisma));
    expect(resultado.tipo).toBe("ENTRADA");
    expect(resultado.registro.conceptoCodigo).toBe("DFC");
  });

  test("festivo en su día de descanso + plaza CON compensatorio -> DFC", async () => {
    congelarFecha(new Date(2026, 3, 4, 9, 0, 0));
    const { prisma } = construirPrisma({
      festivos: [{ fecha: SABADO_FESTIVO }],
      necesidad: { descansoCompensatorio: true },
    });
    expect((await checkin(new AsistenciaService(prisma))).registro.conceptoCodigo).toBe("DFC");
  });

  test("festivo en su día de descanso + plaza SIN compensatorio -> DFP", async () => {
    congelarFecha(new Date(2026, 3, 4, 9, 0, 0));
    const { prisma } = construirPrisma({
      festivos: [{ fecha: SABADO_FESTIVO }],
      necesidad: { descansoCompensatorio: false },
    });
    expect((await checkin(new AsistenciaService(prisma))).registro.conceptoCodigo).toBe("DFP");
  });

  test("festivo en un día que igual trabaja (no genera compensatorio) -> DFP aunque la plaza lo tenga", async () => {
    congelarFecha(new Date(2026, 3, 1, 9, 0, 0));
    const { prisma } = construirPrisma({
      festivos: [{ fecha: MIERCOLES_FESTIVO }],
      necesidad: { descansoCompensatorio: true },
    });
    expect((await checkin(new AsistenciaService(prisma))).registro.conceptoCodigo).toBe("DFP");
  });

  test("trabajar su día de descanso (domingo, sin festivo) con plaza con compensatorio -> DFC", async () => {
    congelarFecha(new Date(2026, 3, 5, 9, 0, 0)); // domingo
    const { prisma } = construirPrisma({ festivos: [], necesidad: { descansoCompensatorio: true } });
    expect((await checkin(new AsistenciaService(prisma))).registro.conceptoCodigo).toBe("DFC");
  });

  test("festivo + operario SIN plaza -> se conserva 'A' con nota pendiente", async () => {
    congelarFecha(new Date(2026, 3, 4, 9, 0, 0));
    const { prisma } = construirPrisma({ festivos: [{ fecha: SABADO_FESTIVO }], necesidad: null });
    const resultado = await checkin(new AsistenciaService(prisma));
    expect(resultado.registro.conceptoCodigo).toBe("A");
    expect(resultado.registro.observacion).toMatch(/pendiente clasificar/i);
  });

  test("día normal (martes, sin festivo) registra 'A' sin observación", async () => {
    congelarFecha(new Date(2026, 3, 7, 9, 0, 0));
    const { prisma } = construirPrisma({ festivos: [], necesidad: { descansoCompensatorio: true } });
    const resultado = await checkin(new AsistenciaService(prisma));
    expect(resultado.registro.conceptoCodigo).toBe("A");
    expect(resultado.registro.observacion).toBeNull();
  });
});
