import { CanalPago, EstadoCobro } from "@prisma/client";
import { crearFakePagosPrisma } from "../helpers/fakePagosPrisma";

const crearCobroFactus = jest.fn();
const consultarCobroFactus = jest.fn();

jest.mock("../../src/services/pagos/FactusPayClient", () => ({
  ...jest.requireActual("../../src/services/pagos/FactusPayClient"),
  crearCobroFactus: (...args: unknown[]) => crearCobroFactus(...args),
  consultarCobroFactus: (...args: unknown[]) => consultarCobroFactus(...args),
  isFactusPayConfigured: () => true,
}));

// Conteos de ventana deterministas (sin Redis ni estado entre pruebas).
const contarEnVentana = jest.fn();
jest.mock("../../src/middlewares/rate-limit.middleware", () => ({
  contarEnVentana: (...args: unknown[]) => contarEnVentana(...args),
}));
jest.mock("../../src/services/RedisService", () => ({
  cacheGet: jest.fn().mockResolvedValue(null),
  cacheSet: jest.fn().mockResolvedValue(undefined),
}));

import { FactusWebhookService, llaveWebhookValida } from "../../src/services/pagos/FactusWebhookService";
import { PagoService } from "../../src/services/pagos/PagoService";

const LLAVE = "k".repeat(40);
const LLAVE_ANTERIOR = "a".repeat(40);
const IP = "203.0.113.7";

function coleccion(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    reference_code: "CA-x",
    amount: 50_000,
    status: "ready",
    created_at: new Date().toISOString(),
    qr: "x",
    ...overrides,
  };
}

function cuerpo(referenceCode: string, overrides: Record<string, unknown> = {}) {
  return {
    data: {
      reference_code: referenceCode,
      amount: 50_000,
      status: "paid",
      created_at: "2026-10-14T15:20:00.000000Z",
      qr_expires_at: "2026-10-15T15:20:00Z",
      payer: { name: "Juan Perez", document_type: "CC", document_number: "1234567890" },
      qr: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA",
      ...overrides,
    },
  };
}

async function armar(opciones: { sandbox?: boolean } = {}) {
  crearCobroFactus.mockImplementation(async (ref: string) => coleccion({ reference_code: ref }));
  const prisma = crearFakePagosPrisma();
  const pagos = new PagoService(prisma);
  const confirmador = jest.fn().mockResolvedValue(undefined);
  const posFallo = jest.fn().mockResolvedValue(undefined);
  pagos.registrarConfirmador(CanalPago.CONTROLAPP, confirmador);
  pagos.registrarPosFallo(CanalPago.CONTROLAPP, posFallo);
  pagos.registrarAlertador(jest.fn().mockResolvedValue(undefined));
  const consultarDesconocida = jest.fn();
  const alertar = jest.fn().mockResolvedValue(undefined);
  const webhook = new FactusWebhookService(
    prisma,
    pagos,
    consultarDesconocida,
    alertar,
    () => opciones.sandbox ?? false,
  );
  const cobro = await pagos.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
  return { prisma, pagos, webhook, cobro, confirmador, posFallo, consultarDesconocida, alertar };
}

function entrada(body: unknown, key: unknown = LLAVE) {
  return { key, body, rawBody: Buffer.from(JSON.stringify(body)), ip: IP };
}

/** Deja la fila lista para que el barrido o un nuevo intento la tome ya. */
async function vencerEspera(prisma: any, id: number) {
  await prisma.pagoWebhookFactus.update({
    where: { id },
    data: { lockedUntil: new Date(Date.now() - 1_000), recibidoEn: new Date(Date.now() - 60_000) },
  });
}

let warnSpy: jest.SpyInstance;

beforeEach(() => {
  crearCobroFactus.mockReset();
  consultarCobroFactus.mockReset();
  contarEnVentana.mockReset().mockResolvedValue({ count: 1, resetMs: 1_000 });
  process.env.FACTUS_PAY_WEBHOOK_KEY = LLAVE;
  delete process.env.FACTUS_PAY_WEBHOOK_KEY_ANTERIOR;
  warnSpy = jest.spyOn(console, "warn").mockImplementation(() => undefined);
  jest.spyOn(console, "error").mockImplementation(() => undefined);
  jest.spyOn(console, "info").mockImplementation(() => undefined);
});

afterEach(() => {
  delete process.env.FACTUS_PAY_WEBHOOK_KEY;
  delete process.env.FACTUS_PAY_WEBHOOK_KEY_ANTERIOR;
  jest.restoreAllMocks();
});

describe("llaveWebhookValida", () => {
  test("acepta la vigente y la anterior; rechaza otra, vacia, ausente o repetida en la query", () => {
    expect(llaveWebhookValida(LLAVE, [LLAVE, LLAVE_ANTERIOR])).toBe(true);
    expect(llaveWebhookValida(LLAVE_ANTERIOR, [LLAVE, LLAVE_ANTERIOR])).toBe(true);
    expect(llaveWebhookValida(`${LLAVE}x`, [LLAVE])).toBe(false);
    expect(llaveWebhookValida("", [LLAVE])).toBe(false);
    expect(llaveWebhookValida(undefined, [LLAVE])).toBe(false);
    // ?key=a&key=b llega como arreglo.
    expect(llaveWebhookValida([LLAVE, LLAVE], [LLAVE])).toBe(false);
  });
});

describe("FactusWebhookService.recibir", () => {
  test("sin llave configurada responde 503 y no guarda nada", async () => {
    const { webhook, prisma, cobro } = await armar();
    delete process.env.FACTUS_PAY_WEBHOOK_KEY;

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));

    expect(r.status).toBe(503);
    expect(prisma._debug.webhooks()).toHaveLength(0);
  });

  test("una llave configurada demasiado corta deja el endpoint apagado (503)", async () => {
    const { webhook, cobro } = await armar();
    process.env.FACTUS_PAY_WEBHOOK_KEY = "corta";

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode), "corta"));
    expect(r.status).toBe(503);
  });

  test("llave invalida: 401, nada guardado y la llave recibida nunca va al log", async () => {
    const { webhook, prisma, cobro } = await armar();
    const falsa = "f".repeat(40);

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode), falsa));

    expect(r.status).toBe(401);
    expect(r.webhookId).toBeUndefined();
    expect(prisma._debug.webhooks()).toHaveLength(0);
    expect(JSON.stringify(warnSpy.mock.calls)).not.toContain(falsa);
  });

  test("demasiadas llaves invalidas desde la misma IP: 429 y una alerta al llegar a la mitad", async () => {
    const { webhook, cobro, alertar } = await armar();
    contarEnVentana.mockResolvedValueOnce({ count: 10, resetMs: 1 });
    await webhook.recibir(entrada(cuerpo(cobro.referenceCode), "x".repeat(40)));
    expect(alertar).toHaveBeenCalledTimes(1);

    contarEnVentana.mockResolvedValueOnce({ count: 21, resetMs: 1 });
    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode), "x".repeat(40)));
    expect(r.status).toBe(429);
  });

  test("acepta la llave anterior mientras se rota", async () => {
    const { webhook, cobro } = await armar();
    process.env.FACTUS_PAY_WEBHOOK_KEY_ANTERIOR = LLAVE_ANTERIOR;

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode), LLAVE_ANTERIOR));
    expect(r.status).toBe(200);
  });

  test("aviso valido: lo guarda (sin QR ni documento completo), marca el cobro y responde 200 sin confirmar nada", async () => {
    const { webhook, prisma, cobro, confirmador } = await armar();

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));

    expect(r).toMatchObject({ status: 200, body: { received: true } });
    expect(r.webhookId).toBeDefined();
    const [fila] = prisma._debug.webhooks();
    expect(fila).toMatchObject({ estado: "RECIBIDO", cobroId: cobro.id, referenceCode: cobro.referenceCode, ip: IP });
    expect(fila.bodySha256).toMatch(/^[a-f0-9]{64}$/);
    expect(JSON.stringify(fila.payload)).not.toContain("iVBORw0K");
    expect(JSON.stringify(fila.payload)).not.toContain("1234567890");
    expect(fila.payload.payer).toMatchObject({ name: "Juan Perez", document_number_ultimos4: "7890" });

    const actualizado = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(actualizado.webhooksRecibidos).toBe(1);
    expect(actualizado.webhookPrimeroEn).toBeInstanceOf(Date);
    expect(actualizado.estado).not.toBe(EstadoCobro.PAGADO);
    expect(prisma._debug.eventos().some((e: { tipo: string }) => e.tipo === "WEBHOOK_RECIBIDO")).toBe(true);
    // Recibir no consulta a Factus ni confirma: eso pasa despues de responder.
    expect(consultarCobroFactus).not.toHaveBeenCalled();
    expect(confirmador).not.toHaveBeenCalled();
  });

  test("aviso con la llave valida pero sin referencia legible: queda como constancia y no se procesa", async () => {
    const { webhook, prisma } = await armar();

    const r = await webhook.recibir(entrada({ otra: "cosa" }));

    expect(r.status).toBe(200);
    expect(r.webhookId).toBeUndefined();
    expect(prisma._debug.webhooks()[0]).toMatchObject({ estado: "PROCESADO", resultado: "PAYLOAD_INVALIDO" });
  });

  test("demasiados avisos validos desde la misma IP: 429 (Factus reintenta despues)", async () => {
    const { webhook, cobro, prisma } = await armar();
    contarEnVentana.mockResolvedValueOnce({ count: 5_000, resetMs: 1 });

    const r = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    expect(r.status).toBe(429);
    expect(prisma._debug.webhooks()).toHaveLength(0);
  });
});

describe("FactusWebhookService.procesar (la API decide)", () => {
  test("Factus confirma por API: el cobro queda PAGADO con origen WEBHOOK", async () => {
    const { webhook, prisma, cobro, confirmador } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    consultarCobroFactus.mockResolvedValue(coleccion({ reference_code: cobro.referenceCode, status: "paid" }));

    await webhook.procesar(webhookId!);

    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final).toMatchObject({ estado: EstadoCobro.PAGADO, origenConfirmacion: "WEBHOOK" });
    expect(confirmador).toHaveBeenCalledTimes(1);
    expect(prisma._debug.webhooks()[0]).toMatchObject({ estado: "PROCESADO", resultado: "CONFIRMADO" });
    // La API no informo el pagador: se completa con el del aviso (recortado).
    expect(final).toMatchObject({ pagadorNombre: "Juan Perez", pagadorDocumentoUltimos4: "7890" });
  });

  test("aviso falso (la API dice ready): no confirma, reintenta 3 veces y despues alerta", async () => {
    const { webhook, prisma, cobro, confirmador, alertar } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    consultarCobroFactus.mockResolvedValue(coleccion({ reference_code: cobro.referenceCode, status: "ready" }));

    for (let intento = 1; intento <= 3; intento++) {
      await webhook.procesar(webhookId!);
      const fila = prisma._debug.webhooks()[0];
      expect(fila.estado).toBe("RECIBIDO");
      expect(fila.lockedUntil.getTime()).toBeGreaterThan(Date.now());
      await vencerEspera(prisma, webhookId!);
    }
    await webhook.procesar(webhookId!);

    const fila = prisma._debug.webhooks()[0];
    expect(fila).toMatchObject({ estado: "PROCESADO", resultado: "NO_CONFIRMADO_POR_API" });
    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.estado).not.toBe(EstadoCobro.PAGADO);
    expect(confirmador).not.toHaveBeenCalled();
    expect(alertar).toHaveBeenCalledTimes(1);
    expect(consultarCobroFactus).toHaveBeenCalledTimes(4);
  });

  test("monto alterado en el aviso: decide la API (monto correcto) y queda anotado", async () => {
    const { webhook, prisma, cobro } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode, { amount: 5_000 })));
    consultarCobroFactus.mockResolvedValue(coleccion({ reference_code: cobro.referenceCode, status: "paid" }));

    await webhook.procesar(webhookId!);

    const fila = prisma._debug.webhooks()[0];
    expect(fila.resultado).toBe("CONFIRMADO");
    expect(fila.detalle).toContain("5000");
  });

  test("la API confirma un monto distinto al del cobro: DISCREPANCIA, sin confirmar el pedido", async () => {
    const { webhook, prisma, cobro, confirmador } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    consultarCobroFactus.mockResolvedValue(
      coleccion({ reference_code: cobro.referenceCode, status: "paid", amount: 25_000 }),
    );

    await webhook.procesar(webhookId!);

    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).estado).toBe(EstadoCobro.DISCREPANCIA);
    expect(confirmador).not.toHaveBeenCalled();
    expect(prisma._debug.webhooks()[0].resultado).toBe("DISCREPANCIA");
  });

  test("diez entregas iguales y simultaneas: el pedido se confirma una sola vez", async () => {
    const { webhook, prisma, cobro, confirmador } = await armar();
    consultarCobroFactus.mockResolvedValue(coleccion({ reference_code: cobro.referenceCode, status: "paid" }));
    const ids: number[] = [];
    for (let i = 0; i < 10; i++) {
      ids.push((await webhook.recibir(entrada(cuerpo(cobro.referenceCode)))).webhookId!);
    }

    await Promise.all(ids.map((id) => webhook.procesar(id)));
    // Las que encontraron el cobro ocupado quedaron para el barrido.
    for (const id of ids) await vencerEspera(prisma, id);
    await webhook.barrerPendientes(50);

    expect(confirmador).toHaveBeenCalledTimes(1);
    const filas = prisma._debug.webhooks();
    expect(filas.every((f: { estado: string }) => f.estado === "PROCESADO")).toBe(true);
    expect(filas.filter((f: { resultado: string }) => f.resultado === "CONFIRMADO")).toHaveLength(1);
    expect(filas.filter((f: { resultado: string }) => f.resultado === "YA_PROCESADO")).toHaveLength(9);
    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).webhooksRecibidos).toBe(10);
  });

  test("replay de un aviso de un cobro ya pagado: YA_PROCESADO sin volver a consultar", async () => {
    const { webhook, prisma, cobro, confirmador } = await armar();
    consultarCobroFactus.mockResolvedValue(coleccion({ reference_code: cobro.referenceCode, status: "paid" }));
    await webhook.procesar((await webhook.recibir(entrada(cuerpo(cobro.referenceCode)))).webhookId!);
    consultarCobroFactus.mockClear();

    await webhook.procesar((await webhook.recibir(entrada(cuerpo(cobro.referenceCode)))).webhookId!);

    expect(consultarCobroFactus).not.toHaveBeenCalled();
    expect(confirmador).toHaveBeenCalledTimes(1);
    expect(prisma._debug.webhooks()[1].resultado).toBe("YA_PROCESADO");
  });

  test("cobro FALLIDO aqui: se reabre solo si la API dice paid, y un aviso falso no repite el aviso de pago fallido", async () => {
    const { webhook, prisma, cobro, posFallo } = await armar();
    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { estado: EstadoCobro.FALLIDO } });
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));

    consultarCobroFactus.mockResolvedValueOnce(coleccion({ reference_code: cobro.referenceCode, status: "rejected" }));
    await webhook.procesar(webhookId!);
    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).estado).toBe(EstadoCobro.FALLIDO);
    expect(posFallo).not.toHaveBeenCalled();

    await vencerEspera(prisma, webhookId!);
    consultarCobroFactus.mockResolvedValueOnce(coleccion({ reference_code: cobro.referenceCode, status: "paid" }));
    await webhook.procesar(webhookId!);
    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).estado).toBe(EstadoCobro.PAGADO);
  });

  test("referencia de otro sistema o del sandbox: solo constancia, sin consultar a Factus", async () => {
    const ajena = await armar();
    await ajena.webhook.procesar((await ajena.webhook.recibir(entrada(cuerpo("FACT-00123")))).webhookId!);
    expect(ajena.consultarDesconocida).not.toHaveBeenCalled();
    expect(ajena.prisma._debug.webhooks()[0].resultado).toBe("REFERENCIA_DESCONOCIDA");

    const sandbox = await armar({ sandbox: true });
    await sandbox.webhook.procesar((await sandbox.webhook.recibir(entrada(cuerpo("CA-de-otro-entorno")))).webhookId!);
    expect(sandbox.consultarDesconocida).not.toHaveBeenCalled();
    expect(sandbox.alertar).not.toHaveBeenCalled();
  });

  test("referencia nuestra que no existe aqui (produccion): alerta solo si Factus confirma el pago", async () => {
    const real = await armar();
    real.consultarDesconocida.mockResolvedValue(coleccion({ reference_code: "CA-perdido", status: "paid" }));
    await real.webhook.procesar((await real.webhook.recibir(entrada(cuerpo("CA-perdido")))).webhookId!);
    expect(real.alertar).toHaveBeenCalledTimes(1);

    const falsa = await armar();
    falsa.consultarDesconocida.mockResolvedValue(null);
    await falsa.webhook.procesar((await falsa.webhook.recibir(entrada(cuerpo("CA-inventado")))).webhookId!);
    expect(falsa.alertar).not.toHaveBeenCalled();
    expect(falsa.prisma._debug.webhooks()[0].resultado).toBe("REFERENCIA_DESCONOCIDA");
  });

  test("Factus caido al verificar: la fila queda para reintento y el cobro sigue igual", async () => {
    const { webhook, prisma, cobro } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    consultarCobroFactus.mockRejectedValue(new Error("timeout"));

    await webhook.procesar(webhookId!);

    expect(prisma._debug.webhooks()[0].estado).toBe("RECIBIDO");
    expect((await prisma.pagoCobro.findUnique({ where: { id: cobro.id } })).estado).toBe(EstadoCobro.PENDIENTE);
  });

  test("un error inesperado reintenta y, tras 5 intentos, cierra la fila como ERROR y alerta", async () => {
    const { webhook, prisma, pagos, cobro, alertar } = await armar();
    const { webhookId } = await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    jest.spyOn(pagos, "verificarCobro").mockRejectedValue(new Error("db caida"));

    for (let intento = 1; intento <= 5; intento++) {
      await webhook.procesar(webhookId!);
      await vencerEspera(prisma, webhookId!);
    }

    expect(prisma._debug.webhooks()[0]).toMatchObject({ estado: "PROCESADO", resultado: "ERROR" });
    expect(alertar).toHaveBeenCalledTimes(1);
  });

  test("el barrido no toma avisos recien llegados (los procesa el propio request)", async () => {
    const { webhook, cobro } = await armar();
    await webhook.recibir(entrada(cuerpo(cobro.referenceCode)));
    const procesar = jest.spyOn(webhook, "procesar");

    await webhook.barrerPendientes();

    expect(procesar).not.toHaveBeenCalled();
  });
});
