import { EstadoPedidoInterno, Prisma, Rol, TipoPedidoApp } from "@prisma/client";
import { CommerceOrderService } from "../../src/services/CommerceOrderService";

function product(overrides: Record<string, unknown> = {}) {
  return {
    id: 72,
    name: "Detergente institucional",
    slug: "detergente-institucional",
    type: "simple",
    sku: "DET-72",
    shortDescription: "",
    description: "",
    permalink: "",
    onSale: false,
    purchasable: true,
    stockStatus: "instock",
    lowStockRemaining: null,
    price: {
      currencyCode: "COP",
      currencySymbol: "$",
      current: 25000,
      regular: 25000,
      sale: 0,
    },
    images: [],
    categories: [],
    tags: [],
    averageRating: 0,
    reviewCount: 0,
    audience: {
      paraResidente: true,
      paraConjunto: true,
      esServicio: false,
    },
    searchableText: "",
    source: "woo_store_api",
    ...overrides,
  };
}

function orderRecord() {
  const now = new Date("2026-08-04T12:00:00.000Z");
  return {
    id: 10,
    wooOrderId: "991",
    estado: EstadoPedidoInterno.PENDIENTE_PAGO,
    estadoWoo: "pending",
    total: new Prisma.Decimal(50000),
    moneda: "COP",
    conjuntoId: "900100200-1",
    creadoEn: now,
    actualizadoEn: now,
    conjunto: { nombre: "Conjunto Los Pinos" },
    items: [
      {
        id: 1,
        nombreProducto: "Detergente institucional",
        sku: "DET-72",
        cantidad: new Prisma.Decimal(2),
        precioUnitario: new Prisma.Decimal(25000),
        subtotal: new Prisma.Decimal(50000),
      },
    ],
  };
}

describe("CommerceOrderService - pedidos de conjunto", () => {
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

  test("crea una orden de administrador con metadatos y persistencia CONJUNTO", async () => {
    const prisma = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "admin-1",
          nombre: "Ana Torres",
          correo: "ana@example.test",
          rol: Rol.administrador,
          gerente: null,
          jefeOperaciones: null,
        }),
      },
      conjunto: {
        findFirst: jest.fn().mockResolvedValue({
          nit: "900100200-1",
          nombre: "Conjunto Los Pinos",
          correo: "compras@example.test",
        }),
      },
      pedidoApp: {
        create: jest.fn().mockResolvedValue(orderRecord()),
      },
    };
    const service = new CommerceOrderService(prisma as never);
    jest
      .spyOn((service as any).catalogService, "getProduct")
      .mockResolvedValue(product());
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({
        id: 991,
        status: "pending",
        total: "50000",
        currency: "COP",
        order_key: "wc_key",
      }),
    });
    global.fetch = fetchMock as typeof fetch;

    const result = await service.createConjuntoOrder("admin-1", {
      items: [{ productId: 72, quantity: 2 }],
      notas: "Entregar en porteria",
    });

    expect(prisma.conjunto.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({ administradorId: "admin-1" }),
      }),
    );
    const request = fetchMock.mock.calls[0][1] as RequestInit;
    const wooBody = JSON.parse(String(request.body));
    expect(wooBody.payment_method).toBe("bacs");
    expect(wooBody.status).toBe("pending");
    expect(wooBody.meta_data).toEqual(
      expect.arrayContaining([
        { key: "controlapp_tipo_pedido", value: "CONJUNTO" },
        { key: "controlapp_conjunto_id", value: "900100200-1" },
      ]),
    );
    expect(prisma.pedidoApp.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          tipo: TipoPedidoApp.CONJUNTO,
          residenteId: null,
          conjuntoId: "900100200-1",
        }),
      }),
    );
    expect(result).toEqual(
      expect.objectContaining({
        id: 10,
        conjuntoId: "900100200-1",
        total: 50000,
      }),
    );
  });

  test("impide que un gerente compre para un conjunto de otra empresa", async () => {
    const prisma = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "gerente-1",
          nombre: "Gerente Uno",
          correo: "gerente@example.test",
          rol: Rol.gerente,
          gerente: { empresaId: "EMPRESA-A" },
          jefeOperaciones: null,
        }),
      },
      conjunto: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
    };
    const service = new CommerceOrderService(prisma as never);

    await expect(
      service.createConjuntoOrder("gerente-1", {
        conjuntoId: "CONJUNTO-EXTERNO",
        items: [{ productId: 72, quantity: 1 }],
      }),
    ).rejects.toMatchObject({ status: 403 });
    expect(prisma.conjunto.findFirst).toHaveBeenCalledWith(
      expect.objectContaining({
        where: expect.objectContaining({
          nit: "CONJUNTO-EXTERNO",
          empresaId: "EMPRESA-A",
        }),
      }),
    );
  });

  test("rechaza servicios aunque lleguen manipulados desde el cliente", async () => {
    const prisma = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "admin-1",
          nombre: "Ana Torres",
          correo: "ana@example.test",
          rol: Rol.administrador,
          gerente: null,
          jefeOperaciones: null,
        }),
      },
      conjunto: {
        findFirst: jest.fn().mockResolvedValue({
          nit: "900100200-1",
          nombre: "Conjunto Los Pinos",
          correo: "compras@example.test",
        }),
      },
    };
    const service = new CommerceOrderService(prisma as never);
    jest
      .spyOn((service as any).catalogService, "getProduct")
      .mockResolvedValue(
        product({
          name: "Servicio de fumigacion",
          audience: {
            paraResidente: true,
            paraConjunto: false,
            esServicio: true,
          },
        }),
      );
    const fetchMock = jest.fn();
    global.fetch = fetchMock as typeof fetch;

    await expect(
      service.createConjuntoOrder("admin-1", {
        items: [{ productId: 72, quantity: 1 }],
      }),
    ).rejects.toMatchObject({ status: 400 });
    expect(fetchMock).not.toHaveBeenCalled();
  });

  test("lista solo pedidos de conjuntos pertenecientes a la empresa del jefe", async () => {
    const prisma = {
      usuario: {
        findUnique: jest.fn().mockResolvedValue({
          id: "jefe-1",
          nombre: "Jefe Uno",
          correo: "jefe@example.test",
          rol: Rol.jefe_operaciones,
          gerente: null,
          jefeOperaciones: { empresaId: "EMPRESA-A" },
        }),
      },
      conjunto: {
        findMany: jest.fn().mockResolvedValue([
          { nit: "900100200-1" },
          { nit: "900100200-2" },
        ]),
      },
      pedidoApp: {
        findMany: jest.fn().mockResolvedValue([orderRecord()]),
      },
    };
    const service = new CommerceOrderService(prisma as never);

    const result = await service.listConjuntoOrders("jefe-1");

    expect(prisma.conjunto.findMany).toHaveBeenCalledWith({
      where: { empresaId: "EMPRESA-A" },
      select: { nit: true },
    });
    expect(prisma.pedidoApp.findMany).toHaveBeenCalledWith(
      expect.objectContaining({
        where: {
          tipo: TipoPedidoApp.CONJUNTO,
          conjuntoId: { in: ["900100200-1", "900100200-2"] },
        },
      }),
    );
    expect(result).toHaveLength(1);
  });
});
