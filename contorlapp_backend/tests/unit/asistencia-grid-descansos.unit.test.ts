import { AsistenciaService } from "../../src/services/AsistenciaService";

/**
 * Plaza que trabaja martes a domingo y descansa el lunes, con un festivo un
 * lunes (2026-04-06) que sí trabaja y le da compensatorio.
 * Abril 2026: 1 = miércoles, 6 = lunes, 7 = martes.
 */
function construirPrisma(opts: { festivos: Date[]; trabajaFestivos: boolean }) {
  const DIAS = ["MARTES", "MIERCOLES", "JUEVES", "VIERNES", "SABADO", "DOMINGO"];
  return {
    conceptoAsistencia: {
      count: jest.fn().mockResolvedValue(1),
      createMany: jest.fn(),
    },
    conjunto: { findFirst: jest.fn().mockResolvedValue({ nit: "C-1" }) },
    operario: {
      findMany: jest.fn().mockResolvedValue([
        {
          id: "op-1",
          funciones: ["SALVAVIDAS"],
          usuario: { nombre: "Carlos", rol: "operario" },
          conjuntos: [{ nit: "C-1", nombre: "Conjunto Uno" }],
        },
      ]),
    },
    registroAsistencia: { findMany: jest.fn().mockResolvedValue([]) },
    turnoExtra: { findMany: jest.fn().mockResolvedValue([]) },
    festivo: {
      findMany: jest.fn().mockResolvedValue(opts.festivos.map((fecha) => ({ fecha, nombre: "Festivo" }))),
    },
    conjuntoHorario: {
      findUnique: jest.fn(async ({ where }: any) =>
        DIAS.includes(where.conjuntoId_dia.dia)
          ? { horaApertura: "08:00", horaCierre: "16:00", descansoInicio: null, descansoFin: null }
          : null,
      ),
    },
    conjuntoNecesidadOperario: {
      findMany: jest.fn().mockResolvedValue([
        {
          operarioId: "op-1",
          horarioEspecial: false,
          horarios: [],
          trabajaFestivos: opts.trabajaFestivos,
          festivoHoraApertura: "09:00",
          festivoHoraCierre: "15:00",
          festivoDescansoInicio: null,
          festivoDescansoFin: null,
          descansoCompensatorio: true,
          diasDescansoCompensatorio: 1,
        },
      ]),
    },
    $queryRaw: jest.fn(async () =>
      opts.festivos.map((f) => ({
        fecha_key: `${f.getFullYear()}-${String(f.getMonth() + 1).padStart(2, "0")}-${String(f.getDate()).padStart(2, "0")}`,
      })),
    ),
  } as any;
}

describe("AsistenciaService.getGrid - descansos automáticos", () => {
  afterEach(() => jest.useRealTimers());

  async function dias(prisma: any, hoy: Date) {
    jest.useFakeTimers({ now: hoy, doNotFake: ["nextTick", "setImmediate"] });
    const grid = await new AsistenciaService(prisma).getGrid({
      empresaId: "EMP-1",
      conjuntoId: "C-1",
      anio: 2026,
      mes: 4,
    });
    const por = new Map<string, any>(grid.operarios[0].dias.map((d: any) => [d.fecha, d]));
    return { por, grid };
  }

  test("sin festivos: los lunes son 'D' (descanso normal), no pendientes y sin compensatorio", async () => {
    const { por } = await dias(construirPrisma({ festivos: [], trabajaFestivos: true }), new Date(2026, 3, 20, 10));
    const lunes = por.get("2026-04-06");
    expect(lunes.esDescansoNormal).toBe(true);
    expect(lunes.pendiente).toBe(false);
    expect(lunes.descansoProgramado).toBeNull();
    for (const d of por.values()) expect(d.descansoProgramado).toBeNull();
    // Un día que sí trabaja y ya pasó sin registro sigue siendo pendiente.
    expect(por.get("2026-04-07").pendiente).toBe(true);
    expect(por.get("2026-04-07").esDescansoNormal).toBe(false);
  });

  test("festivo trabajado en su día de descanso: el martes siguiente es compensatorio ('C'), no 'D'", async () => {
    const festivo = new Date(2026, 3, 6);
    const { por } = await dias(construirPrisma({ festivos: [festivo], trabajaFestivos: true }), new Date(2026, 3, 20, 10));
    expect(por.get("2026-04-06").esFestivo).toBe(true);
    expect(por.get("2026-04-06").esDescansoNormal).toBe(false); // lo trabaja
    expect(por.get("2026-04-07").descansoProgramado).toEqual({ origen: "2026-04-06" });
    expect(por.get("2026-04-07").pendiente).toBe(false);
    // Los otros lunes siguen siendo descanso normal.
    expect(por.get("2026-04-13").esDescansoNormal).toBe(true);
    expect(por.get("2026-04-13").descansoProgramado).toBeNull();
  });

  test("festivo que la plaza no trabaja cuenta como día de descanso ('D')", async () => {
    const festivo = new Date(2026, 3, 8); // miércoles
    const { por } = await dias(construirPrisma({ festivos: [festivo], trabajaFestivos: false }), new Date(2026, 3, 20, 10));
    expect(por.get("2026-04-08").esDescansoNormal).toBe(true);
    expect(por.get("2026-04-08").pendiente).toBe(false);
  });

  test("el resumen cuenta los descansos automáticos ya pasados como D y C", async () => {
    jest.useFakeTimers({ now: new Date(2026, 3, 20, 10), doNotFake: ["nextTick", "setImmediate"] });
    const resumen = await new AsistenciaService(
      construirPrisma({ festivos: [new Date(2026, 3, 6)], trabajaFestivos: true }),
    ).getResumen({ empresaId: "EMP-1", conjuntoId: "C-1", anio: 2026, mes: 4 });
    const op = resumen.operarios[0];
    // Lunes 13 (pasado) es D; el lunes 6 es festivo trabajado; el 20 es hoy.
    expect(op.conteoPorConcepto.D).toBeGreaterThanOrEqual(2);
    expect(op.conteoPorConcepto.C).toBe(1);
    expect(op.compensatoriosTomados).toBe(1);
  });
});
