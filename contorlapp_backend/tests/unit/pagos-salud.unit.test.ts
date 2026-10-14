const cacheGet = jest.fn();
const cacheSet = jest.fn();
jest.mock("../../src/services/RedisService", () => ({
  cacheGet: (...args: unknown[]) => cacheGet(...args),
  cacheSet: (...args: unknown[]) => cacheSet(...args),
  incrementWindow: jest.fn().mockResolvedValue(null),
}));

import { siguienteEsperaMs, siguienteEsperaWebhookMs } from "../../src/services/pagos/backoff";
import {
  decidirModo,
  esperaSegunModo,
  SaludPagosService,
} from "../../src/services/pagos/SaludPagosService";

const MIN = 60_000;
const HORA = 60 * MIN;
const LLAVE = "k".repeat(40);

describe("siguienteEsperaWebhookMs (respaldo con el webhook activo)", () => {
  test("consulta a los 15 min, 1 h, 6 h y 15 min despues de vencer el QR; luego abandona", () => {
    const vigencia = 24 * HORA;
    expect(siguienteEsperaWebhookMs(0, vigencia)).toBe(15 * MIN);
    expect(siguienteEsperaWebhookMs(15 * MIN, vigencia)).toBe(45 * MIN);
    expect(siguienteEsperaWebhookMs(HORA, vigencia)).toBe(5 * HORA);
    expect(siguienteEsperaWebhookMs(6 * HORA, vigencia)).toBe(18 * HORA + 15 * MIN);
    expect(siguienteEsperaWebhookMs(24 * HORA + 15 * MIN, vigencia)).toBeNull();
  });

  test("con un QR corto, la ultima consulta llega antes y se saltan los hitos que no aplican", () => {
    expect(siguienteEsperaWebhookMs(0, 30 * MIN)).toBe(15 * MIN);
    expect(siguienteEsperaWebhookMs(15 * MIN, 30 * MIN)).toBe(30 * MIN);
    expect(siguienteEsperaWebhookMs(45 * MIN, 30 * MIN)).toBeNull();
  });

  test("un cobro abandonado cuesta 4 consultas en vez de cientos", () => {
    const contar = (espera: (edad: number) => number | null) => {
      let edad = 0;
      let consultas = 0;
      for (let paso = espera(edad); paso != null; paso = espera(edad)) {
        edad += paso;
        consultas++;
      }
      return consultas;
    };
    expect(contar((edad) => siguienteEsperaWebhookMs(edad, 24 * HORA))).toBe(4);
    expect(contar(siguienteEsperaMs)).toBeGreaterThan(400);
  });
});

describe("decidirModo", () => {
  test("configurado en polling: siempre sondeo, sin motivo de alarma", () => {
    expect(decidirModo({ configurado: "polling", webhookConfigurado: true, pagosSinWebhook: 0 })).toEqual({
      modo: "polling",
      motivo: null,
    });
  });

  test("webhook sin llave en el servidor: sondeo", () => {
    expect(decidirModo({ configurado: "webhook", webhookConfigurado: false, pagosSinWebhook: 0 }).modo).toBe("polling");
  });

  test("webhook con pagos que se confirmaron sin su aviso: modo degradado (sondeo) con motivo", () => {
    const r = decidirModo({ configurado: "webhook", webhookConfigurado: true, pagosSinWebhook: 2 });
    expect(r.modo).toBe("polling");
    expect(r.motivo).toContain("2 pago(s)");
  });

  test("webhook configurado y llegando: modo webhook", () => {
    expect(decidirModo({ configurado: "webhook", webhookConfigurado: true, pagosSinWebhook: 0 }).modo).toBe("webhook");
  });
});

describe("esperaSegunModo", () => {
  const ahora = new Date("2026-10-14T12:00:00Z");

  test("en sondeo usa el backoff de siempre", () => {
    const cobro = { creadoEn: new Date(ahora.getTime() - MIN), qrExpiraEn: null };
    expect(esperaSegunModo("polling", cobro, ahora)).toBe(10_000);
  });

  test("en modo webhook usa la vigencia real del QR si Factus la informo, o 24 h", () => {
    const creadoEn = new Date(ahora.getTime() - 7 * HORA);
    expect(esperaSegunModo("webhook", { creadoEn, qrExpiraEn: null }, ahora)).toBe(17 * HORA + 15 * MIN);
    const qrExpiraEn = new Date(creadoEn.getTime() + 8 * HORA);
    expect(esperaSegunModo("webhook", { creadoEn, qrExpiraEn }, ahora)).toBe(HORA + 15 * MIN);
  });
});

describe("SaludPagosService", () => {
  function armar(pagosSinWebhook = 0) {
    const prisma: any = {
      pagoCobro: {
        count: jest.fn().mockResolvedValue(pagosSinWebhook),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
        groupBy: jest.fn().mockResolvedValue([{ origenConfirmacion: "WEBHOOK", _count: { _all: 3 } }]),
      },
      pagoWebhookFactus: {
        findFirst: jest.fn().mockResolvedValue({ recibidoEn: new Date("2026-10-14T11:00:00Z") }),
        count: jest.fn().mockResolvedValue(4),
        groupBy: jest.fn().mockResolvedValue([{ resultado: "CONFIRMADO", _count: { _all: 3 } }]),
      },
    };
    const alertar = jest.fn().mockResolvedValue(undefined);
    return { prisma, alertar, salud: new SaludPagosService(prisma, alertar) };
  }

  beforeEach(() => {
    cacheGet.mockReset().mockResolvedValue(null);
    cacheSet.mockReset().mockResolvedValue(undefined);
    process.env.FACTUS_PAY_WEBHOOK_KEY = LLAVE;
    process.env.PAGOS_MODO_CONFIRMACION = "webhook";
  });

  afterEach(() => {
    delete process.env.FACTUS_PAY_WEBHOOK_KEY;
    delete process.env.PAGOS_MODO_CONFIRMACION;
  });

  test("arranca en sondeo hasta la primera evaluacion (lo seguro)", () => {
    expect(armar().salud.modoEfectivo()).toBe("polling");
  });

  test("con el webhook llegando pasa al modo webhook y no adelanta consultas", async () => {
    const { salud, prisma, alertar } = armar(0);
    await salud.evaluar();
    expect(salud.modoEfectivo()).toBe("webhook");
    expect(prisma.pagoCobro.updateMany).not.toHaveBeenCalled();
    expect(alertar).not.toHaveBeenCalled();
  });

  test("un pago sin aviso del webhook: vuelve al sondeo, adelanta las consultas agendadas lejos y alerta una vez al dia", async () => {
    const { salud, prisma, alertar } = armar(1);
    await salud.evaluar();

    expect(salud.modoEfectivo()).toBe("polling");
    expect(prisma.pagoCobro.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ data: { proximaVerificacion: expect.any(Date) } }),
    );
    expect(alertar).toHaveBeenCalledTimes(1);
    expect(cacheSet).toHaveBeenCalledWith("pagos:salud:alerta-sin-webhook", true, 24 * 3600);

    cacheGet.mockResolvedValue(true);
    await salud.evaluar();
    expect(alertar).toHaveBeenCalledTimes(1);
  });

  test("sin llave del webhook no cuenta pagos sin aviso ni alerta", async () => {
    delete process.env.FACTUS_PAY_WEBHOOK_KEY;
    const { salud, prisma, alertar } = armar(5);
    await salud.evaluar();
    expect(prisma.pagoCobro.count).not.toHaveBeenCalled();
    expect(alertar).not.toHaveBeenCalled();
    expect(salud.modoEfectivo()).toBe("polling");
  });

  test("evaluarSiToca solo recalcula cada 5 minutos", async () => {
    const { salud, prisma } = armar(0);
    const t0 = new Date("2026-10-14T12:00:00Z");
    await salud.evaluarSiToca(t0);
    await salud.evaluarSiToca(new Date(t0.getTime() + 2 * MIN));
    expect(prisma.pagoCobro.count).toHaveBeenCalledTimes(1);
    await salud.evaluarSiToca(new Date(t0.getTime() + 6 * MIN));
    expect(prisma.pagoCobro.count).toHaveBeenCalledTimes(2);
  });

  test("resumen para el panel", async () => {
    const { salud } = armar(0);
    const r = await salud.resumen();
    expect(r).toMatchObject({
      modoConfigurado: "webhook",
      modoEfectivo: "webhook",
      webhookConfigurado: true,
      avisos24h: 4,
      resultadosAvisos7d: { CONFIRMADO: 3 },
      confirmados7d: { total: 3, porOrigen: { WEBHOOK: 3 } },
      pagosSinWebhook24h: 0,
    });
  });
});
