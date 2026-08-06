import {
  EstadoPedidoInterno,
  Prisma,
  TipoMovimientoInsumo,
  TipoMovimientoPuntos,
  TipoPedidoApp,
} from "@prisma/client";
import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";
import { CommercePointsService } from "../../src/services/CommercePointsService";

function conjuntoOrder(overrides: Record<string, unknown> = {}) {
  return {
    id: 41,
    tipo: TipoPedidoApp.CONJUNTO,
    estado: EstadoPedidoInterno.ENVIADO,
    estadoWoo: "processing",
    wooOrderId: "9001",
    usuarioId: "admin-1",
    conjuntoId: "CJ-1",
    residenteId: null,
    total: new Prisma.Decimal(50000),
    moneda: "COP",
    entradaInventarioAplicada: false,
    entradaInventarioAplicadaEn: null,
    puntosAplicados: false,
    puntosAplicadosEn: null,
    descuentoPuntos: new Prisma.Decimal(0),
    beneficioPuntosId: null,
    creadoEn: new Date("2026-08-04T12:00:00Z"),
    actualizadoEn: new Date("2026-08-04T12:00:00Z"),
    conjunto: { nombre: "Los Pinos", empresaId: "EMP-1" },
    historialEstados: [],
    consumosInventario: [],
    items: [
      {
        id: 7,
        pedidoId: 41,
        wooProductId: 72,
        wooVariationId: null,
        nombreProducto: "Detergente",
        sku: "DET-72",
        cantidad: new Prisma.Decimal(2),
        precioUnitario: new Prisma.Decimal(25000),
        subtotal: new Prisma.Decimal(50000),
        insumoId: 5,
        insumo: {
          id: 5,
          nombre: "Detergente",
          unidad: "UNIDAD",
          empresaId: "EMP-1",
          wooSku: "DET-72",
          wooProductId: 72,
        },
      },
    ],
    ...overrides,
  };
}

describe("CommerceLifecycleService - entrada de inventario", () => {
  test("suma stock, registra ENTRADA y reclama idempotencia una sola vez", async () => {
    const tx = {
      pedidoApp: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      inventario: { upsert: jest.fn().mockResolvedValue({ id: 3 }) },
      inventarioInsumo: { upsert: jest.fn().mockResolvedValue({}) },
      consumoInsumo: { upsert: jest.fn().mockResolvedValue({}) },
    };
    const service = new CommerceLifecycleService({} as never);

    await (service as any).applyInventory(tx, conjuntoOrder());

    expect(tx.pedidoApp.updateMany).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: 41, entradaInventarioAplicada: false } }),
    );
    expect(tx.inventarioInsumo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        update: { cantidad: { increment: new Prisma.Decimal(2) } },
      }),
    );
    expect(tx.consumoInsumo.upsert).toHaveBeenCalledWith(
      expect.objectContaining({
        create: expect.objectContaining({
          pedidoAppId: 41,
          tipo: TipoMovimientoInsumo.ENTRADA,
        }),
      }),
    );
  });

  test("rechaza toda la recepcion si hay un producto sin mapeo", async () => {
    const tx = {
      insumo: {
        findFirst: jest.fn().mockResolvedValue(null),
      },
      pedidoApp: { updateMany: jest.fn() },
    };
    const service = new CommerceLifecycleService({} as never);
    const pedido = conjuntoOrder({
      items: [
        {
          ...conjuntoOrder().items[0],
          insumoId: null,
          insumo: null,
          wooProductId: null,
          sku: "SIN-MAPEO",
        },
      ],
    });

    await expect((service as any).applyInventory(tx, pedido)).rejects.toMatchObject({
      status: 409,
    });
    expect(tx.pedidoApp.updateMany).not.toHaveBeenCalled();
  });
});

describe("CommercePointsService - acumulacion", () => {
  test("acumula al entregar segun la tasa del tipo y marca el pedido", async () => {
    const tx = {
      pedidoApp: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      configPuntosConjunto: {
        findUnique: jest.fn().mockResolvedValue({
          activo: true,
          montoPorPuntoResidente: new Prisma.Decimal(1000),
          montoPorPuntoConjunto: new Prisma.Decimal(5000),
        }),
      },
      movimientoPuntos: { create: jest.fn().mockResolvedValue({}) },
    };
    const service = new CommercePointsService({} as never);

    const points = await service.applyAccumulation(tx as never, {
      id: 41,
      usuarioId: "admin-1",
      conjuntoId: "CJ-1",
      tipo: TipoPedidoApp.CONJUNTO,
      estado: EstadoPedidoInterno.ENTREGADO,
      total: new Prisma.Decimal(50000),
      puntosAplicados: false,
    });

    expect(points).toBe(10);
    expect(tx.movimientoPuntos.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        pedidoId: 41,
        conjuntoId: "CJ-1",
        tipo: TipoMovimientoPuntos.ACUMULACION,
        puntos: 10,
      }),
    });
  });

  test("no duplica movimientos cuando el pedido ya fue procesado", async () => {
    const tx = {
      pedidoApp: { updateMany: jest.fn() },
      movimientoPuntos: { create: jest.fn() },
    };
    const service = new CommercePointsService({} as never);

    const points = await service.applyAccumulation(tx as never, {
      id: 41,
      usuarioId: "admin-1",
      conjuntoId: "CJ-1",
      tipo: TipoPedidoApp.CONJUNTO,
      estado: EstadoPedidoInterno.ENTREGADO,
      total: new Prisma.Decimal(50000),
      puntosAplicados: true,
    });

    expect(points).toBe(0);
    expect(tx.movimientoPuntos.create).not.toHaveBeenCalled();
  });
});
