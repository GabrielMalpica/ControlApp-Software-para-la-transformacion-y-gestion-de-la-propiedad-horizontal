import { EstadoPedidoInterno, Prisma, Rol, TipoPedidoApp } from "@prisma/client";
import { CommerceOrderService } from "../../src/services/CommerceOrderService";

describe("CommerceOrderService - orden de servicio", () => {
  const originalEnv = process.env;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      WOOCOMMERCE_BASE_URL: "https://store.example.test",
      WOOCOMMERCE_API_KEY: "ck_test",
      WOOCOMMERCE_SECRET_KEY: "cs_test",
    };
  });

  afterEach(() => {
    process.env = originalEnv;
    jest.restoreAllMocks();
  });

  test("recalcula precio, reclama cupo e inyecta la meta del plugin", async () => {
    const now = new Date("2026-08-05T12:00:00.000Z");
    const createdOrder = {
      id: 20,
      tipo: TipoPedidoApp.RESIDENTE,
      usuarioId: "resident-1",
      wooOrderId: "1001",
      estado: EstadoPedidoInterno.PENDIENTE_PAGO,
      estadoWoo: "pending",
      total: new Prisma.Decimal(133500),
      moneda: "COP",
      pagarAhora: new Prisma.Decimal(67000),
      fechaServicio: new Date("2099-08-10T00:00:00.000Z"),
      turnoServicio: "Medio dia (manana)",
      opcionPagoServicio: "deposit",
      addonsServicio: [],
      idempotencyKey: "cart-service-1",
      conjuntoId: "900-1",
      residenteId: "res-1",
      entradaInventarioAplicada: false,
      entradaInventarioAplicadaEn: null,
      puntosAplicados: false,
      puntosAplicadosEn: null,
      descuentoPuntos: new Prisma.Decimal(0),
      beneficioPuntosId: null,
      creadoEn: now,
      actualizadoEn: now,
      items: [
        {
          id: 1,
          pedidoId: 20,
          wooProductId: 77,
          wooVariationId: null,
          nombreProducto: "Servicio de fumigacion",
          sku: "SRV-77",
          cantidad: new Prisma.Decimal(1),
          precioUnitario: new Prisma.Decimal(133500),
          subtotal: new Prisma.Decimal(133500),
          pagarAhora: new Prisma.Decimal(67000),
          fechaServicio: new Date("2099-08-10T00:00:00.000Z"),
          turnoServicio: "Medio dia (manana)",
          opcionPagoServicio: "deposit",
          addonsServicio: [],
          insumoId: null,
        },
      ],
    };
    const prisma = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "resident-1",
          nombre: "Rosa Perez",
          correo: "rosa@example.test",
          rol: Rol.residente,
          residente: {
            id: "res-1",
            conjuntoId: "900-1",
            conjunto: { nit: "900-1", nombre: "Los Pinos" },
          },
        }),
      },
      pedidoApp: {
        findUnique: jest.fn().mockResolvedValue(null),
        create: jest.fn().mockResolvedValue(createdOrder),
      },
    };
    const service = new CommerceOrderService(prisma as never);
    const catalog = (service as any).catalogService;
    jest.spyOn(catalog, "getProduct").mockResolvedValue({
      id: 77,
      name: "Servicio de fumigacion",
      type: "simple",
      sku: "SRV-77",
      purchasable: true,
      price: { current: 100000 },
      audience: { paraResidente: true, paraConjunto: false, esServicio: true },
      service: {
        enabled: true,
        depositPct: 50,
        allowFull: true,
        minDays: 0,
        daysAllowed: [1, 2, 3, 4, 5, 6, 7],
        maxPerDay: 1,
        slots: [{ id: "am", label: "Medio dia (manana)", capacity: 2 }],
        showRange: false,
        range: { min: 0, max: 0 },
        addons: [
          {
            id: "tipo",
            label: "Tipo",
            type: "radio",
            required: true,
            group: [{ id: 1, label: "Profundo", price: 33500 }],
          },
        ],
      },
    });
    jest.spyOn(catalog, "getServiceAvailability").mockResolvedValue({
      available: true,
      remaining: 2,
    });
    jest.spyOn(catalog, "claimServiceAvailability").mockResolvedValue({
      token: "a".repeat(64),
    });
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        id: 1001,
        status: "pending",
        currency: "COP",
        order_key: "wc_key",
      }),
    });
    global.fetch = fetchMock as typeof fetch;

    const result = await service.createResidentOrder("resident-1", {
      idempotencyKey: "cart-service-1",
      items: [
        {
          productId: 77,
          quantity: 1,
          service: {
            date: "2099-08-10",
            slot: "am",
            payChoice: "deposit",
            addons: { tipo: [1] },
          },
        },
      ],
    });

    const url = String(fetchMock.mock.calls[0][0]);
    const request = fetchMock.mock.calls[0][1] as RequestInit;
    const body = JSON.parse(String(request.body));
    expect(url).not.toContain("consumer_secret");
    expect(new Headers(request.headers).get("Authorization")).toMatch(/^Basic /);
    expect(body.line_items[0]).toEqual(
      expect.objectContaining({ subtotal: "133500.00", total: "133500.00" }),
    );
    expect(body.line_items[0].meta_data).toEqual(
      expect.arrayContaining([
        { key: "Fecha del servicio", value: "2099-08-10" },
        { key: "Turno", value: "Medio dia (manana)" },
        { key: "Tipo", value: "Profundo" },
        { key: "Pago", value: "Anticipo" },
      ]),
    );
    expect(body.meta_data).toEqual(
      expect.arrayContaining([
        { key: "_clsr_pay_now", value: 67000 },
        { key: "_clsr_slot", value: "am" },
      ]),
    );
    expect(result.pagarAhora).toBe(67000);
  });
});
