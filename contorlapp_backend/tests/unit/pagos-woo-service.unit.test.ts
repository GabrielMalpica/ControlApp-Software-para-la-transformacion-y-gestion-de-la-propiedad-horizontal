import { CanalPago, EstadoCobro, Prisma } from "@prisma/client";

jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));

import { PagoWooService } from "../../src/services/pagos/PagoWooService";
import { wooFetch } from "../../src/services/wooFetch";

const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

function cobro(overrides: Record<string, unknown> = {}) {
  return {
    id: 3,
    referenceCode: "WC-abc",
    canal: CanalPago.WOOCOMMERCE,
    pedidoAppId: null,
    wooOrderId: "900",
    usuarioId: null,
    montoEsperado: new Prisma.Decimal(80000),
    moneda: "COP",
    estado: EstadoCobro.PENDIENTE,
    estadoProveedor: "ready",
    qrBase64: "qr",
    expiraLocalEn: new Date(),
    lockedUntil: null,
    ...overrides,
  } as any;
}

function servicio() {
  const prisma: any = { pedidoApp: { findUnique: jest.fn().mockResolvedValue(null) } };
  const pagos = {
    crearCobro: jest.fn().mockResolvedValue(cobro()),
    verificarCobro: jest.fn().mockResolvedValue(cobro({ estado: EstadoCobro.PAGADO })),
    obtenerCobroPorReferencia: jest.fn().mockResolvedValue(cobro()),
    marcarHuerfano: jest.fn().mockResolvedValue(cobro()),
  };
  const dominio = {
    confirmarPagoSistema: jest.fn().mockResolvedValue(undefined),
    notificarPagoConfirmado: jest.fn().mockResolvedValue(undefined),
  };
  return { service: new PagoWooService(prisma, pagos as any, dominio), prisma, pagos, dominio };
}

const orden = (over: Record<string, unknown> = {}) => ({
  id: 900,
  status: "pending",
  currency: "COP",
  total: "80000.00",
  order_key: "wc_order_key",
  ...over,
});

beforeEach(() => woo.mockReset());

describe("PagoWooService.crearCobro", () => {
  test("relee la orden en Woo y cobra SU total, no el que diga WordPress", async () => {
    const { service, pagos } = servicio();
    woo.mockResolvedValue(orden());

    const res = await service.crearCobro({ wooOrderId: "900", orderKey: "wc_order_key", montoEsperado: 1 });

    expect(pagos.crearCobro).toHaveBeenCalledWith(
      expect.objectContaining({
        canal: CanalPago.WOOCOMMERCE,
        montoEsperado: 80000,
        wooOrderId: "900",
        referencePrefix: "WC",
      }),
    );
    expect(res).toMatchObject({ referenceCode: "WC-abc", montoEsperado: 80000, pagado: false });
    expect(Object.keys(res)).not.toContain("lockedUntil");
  });

  test("clave de orden incorrecta -> 403", async () => {
    const { service, pagos } = servicio();
    woo.mockResolvedValue(orden());
    await expect(service.crearCobro({ wooOrderId: "900", orderKey: "otra" })).rejects.toMatchObject({ status: 403 });
    expect(pagos.crearCobro).not.toHaveBeenCalled();
  });

  test.each(["cancelled", "processing", "completed", "refunded"])("orden en estado %s -> 409", async (status) => {
    const { service } = servicio();
    woo.mockResolvedValue(orden({ status }));
    await expect(service.crearCobro({ wooOrderId: "900", orderKey: "wc_order_key" })).rejects.toMatchObject({
      status: 409,
    });
  });

  test("moneda distinta de COP -> 422", async () => {
    const { service } = servicio();
    woo.mockResolvedValue(orden({ currency: "USD" }));
    await expect(service.crearCobro({ wooOrderId: "900", orderKey: "wc_order_key" })).rejects.toMatchObject({
      status: 422,
    });
  });

  test("si la orden tambien es un pedido de la app, se enlaza; si ya no esta pendiente -> 409", async () => {
    const { service, prisma, pagos } = servicio();
    woo.mockResolvedValue(orden());
    prisma.pedidoApp.findUnique.mockResolvedValue({ id: 41, usuarioId: "u1", estado: "PENDIENTE_PAGO" });
    await service.crearCobro({ wooOrderId: "900", orderKey: "wc_order_key" });
    expect(pagos.crearCobro).toHaveBeenCalledWith(expect.objectContaining({ pedidoAppId: 41, usuarioId: "u1" }));

    prisma.pedidoApp.findUnique.mockResolvedValue({ id: 41, usuarioId: "u1", estado: "PAGADO" });
    await expect(service.crearCobro({ wooOrderId: "900", orderKey: "wc_order_key" })).rejects.toMatchObject({
      status: 409,
    });
  });

  test("un wooOrderId no numerico se rechaza", async () => {
    const { service } = servicio();
    await expect(service.crearCobro({ wooOrderId: "../x", orderKey: "k" })).rejects.toThrow();
  });
});

describe("PagoWooService consulta y verificacion", () => {
  test("un cobro de otro canal no se expone", async () => {
    const { service, pagos } = servicio();
    pagos.obtenerCobroPorReferencia.mockResolvedValue(cobro({ canal: CanalPago.CONTROLAPP }));
    await expect(service.obtenerCobro("CA-1")).rejects.toMatchObject({ status: 404 });
    await expect(service.verificarCobro("CA-1")).rejects.toMatchObject({ status: 404 });
  });

  test("verificarCobro devuelve el cobro ya actualizado", async () => {
    const { service, pagos } = servicio();
    const res = await service.verificarCobro("WC-abc");
    expect(pagos.verificarCobro).toHaveBeenCalledWith(3);
    expect(res.pagado).toBe(true);
  });
});

describe("PagoWooService.posConfirmacion", () => {
  test("orden pendiente: la marca pagada en Woo con la referencia y avisa al cliente", async () => {
    const { service, dominio, pagos } = servicio();
    woo.mockResolvedValue(orden());

    await service.posConfirmacion(cobro({ estado: EstadoCobro.PAGADO }));

    const put = woo.mock.calls.find((c) => (c[1] as RequestInit)?.method === "PUT");
    expect(JSON.parse((put![1] as RequestInit).body as string)).toEqual({
      status: "processing",
      set_paid: true,
      transaction_id: "WC-abc",
    });
    expect(dominio.notificarPagoConfirmado).toHaveBeenCalled();
    expect(pagos.marcarHuerfano).not.toHaveBeenCalled();
  });

  test("orden cancelada mientras se pagaba: NO se toca y el cobro queda huerfano", async () => {
    const { service, pagos } = servicio();
    woo.mockResolvedValue(orden({ status: "cancelled" }));

    await service.posConfirmacion(cobro({ estado: EstadoCobro.PAGADO }));

    expect(pagos.marcarHuerfano).toHaveBeenCalledWith(3, expect.stringContaining("cancelled"));
    expect(woo.mock.calls.some((c) => (c[1] as RequestInit)?.method === "PUT")).toBe(false);
  });

  test("si Woo no responde lanza, para que PagoService reintente", async () => {
    const { service } = servicio();
    woo.mockRejectedValue(new Error("Woo caido"));
    await expect(service.posConfirmacion(cobro({ estado: EstadoCobro.PAGADO }))).rejects.toThrow("Woo caido");
  });

  test("posFallo marca la orden como failed cuando sigue cobrable", async () => {
    const { service } = servicio();
    woo.mockResolvedValue(orden());

    await service.posFallo(cobro({ estado: EstadoCobro.FALLIDO }));

    const put = woo.mock.calls.find((c) => (c[1] as RequestInit)?.method === "PUT");
    expect(JSON.parse((put![1] as RequestInit).body as string)).toEqual({ status: "failed" });
  });

  test("posFallo no toca la orden si ya no es cobrable", async () => {
    const { service } = servicio();
    woo.mockResolvedValue(orden({ status: "processing" }));

    await service.posFallo(cobro({ estado: EstadoCobro.FALLIDO }));

    expect(woo.mock.calls.some((c) => (c[1] as RequestInit)?.method === "PUT")).toBe(false);
  });

  test("posFallo nunca lanza, aunque Woo falle", async () => {
    const { service } = servicio();
    woo.mockRejectedValue(new Error("Woo caido"));

    await expect(service.posFallo(cobro({ estado: EstadoCobro.FALLIDO }))).resolves.toBeUndefined();
  });

  test("confirmarEnDominio solo mueve un pedido cuando la orden tambien lo es", async () => {
    const { service, dominio } = servicio();
    const tx: any = {};
    const base = {
      cobroId: 3,
      wooOrderId: "900",
      montoEsperado: new Prisma.Decimal(1),
      referenceCode: "WC-abc",
    };
    await service.confirmarEnDominio(tx, { ...base, pedidoAppId: null, usuarioId: null });
    expect(dominio.confirmarPagoSistema).not.toHaveBeenCalled();
    await service.confirmarEnDominio(tx, { ...base, pedidoAppId: 41, usuarioId: "u" });
    expect(dominio.confirmarPagoSistema).toHaveBeenCalledTimes(1);
  });
});
