// Asistencia por QR marcada sin señal en la app Android y enviada después:
// vale la hora del escaneo (día, festivo y descanso incluidos), el reintento no
// registra dos veces y lo que llega muy tarde se rechaza con código.
import { AsistenciaService, resolverMomentoEscaneo } from "../../src/services/AsistenciaService";

const CONCEPTOS = [
  { id: 1, empresaId: "EMP-1", codigo: "A", nombre: "Asistencia", colorHex: "#0C6B43" },
];

function construirPrisma() {
  const registros = new Map<string, any>();
  const idempotencias = new Map<string, any>();
  let secuencia = 100;

  const prisma: any = {
    conjunto: {
      findUnique: jest.fn().mockResolvedValue({
        nit: "C-1",
        nombre: "Conjunto Uno",
        qrAsistenciaToken: "tok-1",
        latitud: 4.7,
        longitud: -74.05,
        radioAsistenciaMetros: 150,
      }),
    },
    operario: { findUnique: jest.fn().mockResolvedValue({ id: "op-1", empresaId: "EMP-1" }) },
    conceptoAsistencia: {
      count: jest.fn().mockResolvedValue(CONCEPTOS.length),
      createMany: jest.fn().mockResolvedValue({ count: 0 }),
      findUnique: jest.fn(async ({ where }: any) =>
        CONCEPTOS.find((c) => c.codigo === where.empresaId_codigo.codigo) ?? null,
      ),
    },
    festivo: { findFirst: jest.fn().mockResolvedValue(null) },
    conjuntoHorario: {
      findUnique: jest.fn().mockResolvedValue({
        horaApertura: "06:00",
        horaCierre: "18:00",
        descansoInicio: null,
        descansoFin: null,
      }),
    },
    conjuntoNecesidadOperario: {
      findMany: jest.fn().mockResolvedValue([]),
      findFirst: jest.fn().mockResolvedValue(null),
    },
    registroAsistencia: {
      findUnique: jest.fn(async ({ where, include }: any) => {
        if (where.id != null) {
          const r = Array.from(registros.values()).find((x) => x.id === where.id) ?? null;
          return r && include?.conjunto ? { ...r, conjunto: { nombre: "Conjunto Uno" } } : r;
        }
        const key = `${where.operarioId_fecha.operarioId}|${where.operarioId_fecha.fecha.toISOString()}`;
        return registros.get(key) ?? null;
      }),
      create: jest.fn(async ({ data }: any) => {
        const creado = { id: ++secuencia, ...data, concepto: CONCEPTOS[0] };
        registros.set(`${data.operarioId}|${data.fecha.toISOString()}`, creado);
        return creado;
      }),
      update: jest.fn(async ({ where, data }: any) => {
        const entry = Array.from(registros.values()).find((r) => r.id === where.id);
        Object.assign(entry, data);
        return entry;
      }),
    },
    asistenciaIdempotencia: {
      findUnique: jest.fn(async ({ where }: any) => idempotencias.get(where.clienteRegistroId) ?? null),
      create: jest.fn(async ({ data }: any) => {
        idempotencias.set(data.clienteRegistroId, data);
        return data;
      }),
    },
  };
  prisma.$transaction = jest.fn(async (fn: any) => fn(prisma));
  return { prisma, registros };
}

const QR = "CTRLAPP-ASISTENCIA|C-1|tok-1";
const ID_1 = "33333333-3333-4333-8333-333333333333";
const ID_2 = "44444444-4444-4444-8444-444444444444";

describe("asistencia por QR sin señal", () => {
  afterEach(() => {
    jest.useRealTimers();
    delete process.env.ASISTENCIA_SIN_SENAL_MAX_HORAS;
  });

  test("vale la hora y el día del escaneo, no los de llegada", async () => {
    // Escaneó el lunes 2 a las 6:55 a. m. sin señal; llegó el martes 3 en la noche.
    jest.useFakeTimers({ now: new Date(2026, 10, 3, 20, 0, 0), doNotFake: ["nextTick", "setImmediate"] });
    const { prisma } = construirPrisma();
    const service = new AsistenciaService(prisma);
    const escaneo = new Date(2026, 10, 2, 6, 55, 0);

    const r = await service.checkin({
      operarioId: "op-1",
      conjuntoId: "C-1",
      qrPayload: QR,
      latitud: 4.7,
      longitud: -74.05,
      clienteRegistroId: ID_1,
      registradaEn: escaneo.toISOString(),
      sinConexion: true,
      horaDispositivoEnvio: new Date(2026, 10, 3, 20, 0, 0).toISOString(),
    });

    expect(r.tipo).toBe("ENTRADA");
    expect(new Date(r.registro.horaEntrada as any).getTime()).toBe(escaneo.getTime());
    expect(r.registro.entradaSinConexion).toBe(true);
    const data = prisma.registroAsistencia.create.mock.calls[0][0].data;
    expect(data.fecha.toISOString()).toBe("2026-11-02T00:00:00.000Z");
    expect(data.entradaRecibidaEn).toBeInstanceOf(Date);
  });

  test("el reintento con el mismo id devuelve lo mismo sin registrar otra vez", async () => {
    jest.useFakeTimers({ now: new Date(2026, 10, 2, 18, 0, 0), doNotFake: ["nextTick", "setImmediate"] });
    const { prisma } = construirPrisma();
    const service = new AsistenciaService(prisma);
    const base = {
      operarioId: "op-1",
      conjuntoId: "C-1",
      qrPayload: QR,
      latitud: 4.7,
      longitud: -74.05,
      sinConexion: true,
    };

    const entrada = await service.checkin({ ...base, clienteRegistroId: ID_1, registradaEn: new Date(2026, 10, 2, 7).toISOString() });
    const salida = await service.checkin({ ...base, clienteRegistroId: ID_2, registradaEn: new Date(2026, 10, 2, 16).toISOString() });
    const reintento = await service.checkin({ ...base, clienteRegistroId: ID_2, registradaEn: new Date(2026, 10, 2, 16).toISOString() });

    expect(entrada.tipo).toBe("ENTRADA");
    expect(salida.tipo).toBe("SALIDA");
    expect(reintento).toMatchObject({ tipo: "SALIDA", duplicado: true });
    expect(prisma.registroAsistencia.update).toHaveBeenCalledTimes(1);
  });

  test("una salida con hora anterior a la entrada se rechaza con código", async () => {
    jest.useFakeTimers({ now: new Date(2026, 10, 2, 18, 0, 0), doNotFake: ["nextTick", "setImmediate"] });
    const { prisma } = construirPrisma();
    const service = new AsistenciaService(prisma);
    const base = { operarioId: "op-1", conjuntoId: "C-1", qrPayload: QR, latitud: 4.7, longitud: -74.05, sinConexion: true };
    await service.checkin({ ...base, clienteRegistroId: ID_1, registradaEn: new Date(2026, 10, 2, 9).toISOString() });
    await expect(
      service.checkin({ ...base, clienteRegistroId: ID_2, registradaEn: new Date(2026, 10, 2, 8).toISOString() }),
    ).rejects.toMatchObject({ status: 409, code: "ASISTENCIA_ORDEN_INVALIDO" });
  });

  test("lo que llega después de la ventana se rechaza; sin 'sinConexion' manda el servidor", () => {
    const recibido = new Date("2026-11-10T12:00:00.000Z");
    expect(() =>
      resolverMomentoEscaneo(
        { sinConexion: true, registradaEn: "2026-11-01T12:00:00.000Z" },
        recibido,
      ),
    ).toThrow(expect.objectContaining({ code: "ASISTENCIA_FUERA_DE_VENTANA" }));

    process.env.ASISTENCIA_SIN_SENAL_MAX_HORAS = "240";
    expect(
      resolverMomentoEscaneo({ sinConexion: true, registradaEn: "2026-11-01T12:00:00.000Z" }, recibido).ahora.toISOString(),
    ).toBe("2026-11-01T12:00:00.000Z");

    const enLinea = resolverMomentoEscaneo({ registradaEn: "2026-11-01T12:00:00.000Z" }, recibido);
    expect(enLinea).toMatchObject({ ahora: recibido, sinConexion: false });
  });

  test("QR reemplazado mientras estaba sin señal → QR_INVALIDO", async () => {
    const { prisma } = construirPrisma();
    await expect(
      new AsistenciaService(prisma).checkin({
        operarioId: "op-1",
        conjuntoId: "C-1",
        qrPayload: "CTRLAPP-ASISTENCIA|C-1|viejo",
        latitud: 4.7,
        longitud: -74.05,
        sinConexion: true,
        registradaEn: new Date().toISOString(),
      }),
    ).rejects.toMatchObject({ status: 400, code: "QR_INVALIDO" });
  });
});
