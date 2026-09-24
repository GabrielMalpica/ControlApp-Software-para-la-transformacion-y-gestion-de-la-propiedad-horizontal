import { EstadoPedidoInterno, Prisma, Rol, TipoPedidoApp } from "@prisma/client";
jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));

import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";
import { wooFetch } from "../../src/services/wooFetch";

const E = EstadoPedidoInterno;

function pedido(estado: EstadoPedidoInterno, overrides: Record<string, unknown> = {}) {
  return {
    id: 41,
    tipo: TipoPedidoApp.CONJUNTO,
    estado,
    usuarioId: "admin-1",
    conjuntoId: "CJ-1",
    total: new Prisma.Decimal(50000),
    comprobanteUrl: null,
    items: [],
    ...overrides,
  };
}

const actor = (rol: Rol) => ({
  id: `${rol}-1`,
  nombre: rol,
  rol,
  empresaId: "EMP-1",
  residente: rol === Rol.residente ? { conjuntoId: "CJ-1" } : null,
});

function permitidas(rol: Rol, estado: EstadoPedidoInterno, overrides = {}) {
  const service = new CommerceLifecycleService({} as never);
  return (service as any).getAllowedTransitions(actor(rol), pedido(estado, overrides));
}

describe("quien puede mover cada estado del pedido", () => {
  describe("personal interno (gerente / jefe de operaciones)", () => {
    test.each([Rol.gerente, Rol.jefe_operaciones])("%s lleva el pedido por pago, preparacion y envio", (rol) => {
      expect(permitidas(rol, E.PENDIENTE_PAGO)).toEqual([E.PAGADO, E.CANCELADO]);
      expect(permitidas(rol, E.PAGADO)).toEqual([E.PENDIENTE_ENVIO, E.CANCELADO]);
      expect(permitidas(rol, E.PENDIENTE_ENVIO)).toEqual([E.ENVIADO, E.CANCELADO]);
      expect(permitidas(rol, E.ENVIADO)).toEqual([E.RECIBIDO]);
    });
  });

  describe("administrador del conjunto (quien compra)", () => {
    test("NO puede confirmar el pago", () => {
      expect(permitidas(Rol.administrador, E.PENDIENTE_PAGO)).not.toContain(E.PAGADO);
    });

    test("NO puede pasar el pedido a en preparacion", () => {
      expect(permitidas(Rol.administrador, E.PAGADO)).toEqual([]);
    });

    test("NO puede marcarlo en camino", () => {
      expect(permitidas(Rol.administrador, E.PENDIENTE_ENVIO)).toEqual([]);
    });

    test("cuando el pedido va en camino, solo puede confirmar que lo recibio", () => {
      expect(permitidas(Rol.administrador, E.ENVIADO)).toEqual([E.RECIBIDO]);
    });

    test("tras recibirlo, confirma la entrega", () => {
      expect(permitidas(Rol.administrador, E.RECIBIDO)).toEqual([E.ENTREGADO]);
    });

    test("puede cancelar solo mientras no ha pagado ni subido comprobante", () => {
      expect(permitidas(Rol.administrador, E.PENDIENTE_PAGO)).toEqual([E.CANCELADO]);
      expect(
        permitidas(Rol.administrador, E.PENDIENTE_PAGO, {
          comprobanteUrl: "https://drive.google.com/file/d/x/view",
        }),
      ).toEqual([]);
      expect(permitidas(Rol.administrador, E.PAGADO)).not.toContain(E.CANCELADO);
    });

    test("un pedido entregado o cancelado no tiene acciones", () => {
      expect(permitidas(Rol.administrador, E.ENTREGADO)).toEqual([]);
      expect(permitidas(Rol.administrador, E.CANCELADO)).toEqual([]);
    });
  });

  describe("residente", () => {
    test("tiene las mismas acciones limitadas que el administrador", () => {
      for (const estado of Object.values(E)) {
        expect(permitidas(Rol.residente, estado)).toEqual(permitidas(Rol.administrador, estado));
      }
    });
  });

  test("ningun rol de quien compra puede ejecutar acciones internas en ningun estado", () => {
    const internas = [E.PAGADO, E.PENDIENTE_ENVIO, E.ENVIADO];
    for (const rol of [Rol.administrador, Rol.residente]) {
      for (const estado of Object.values(E)) {
        for (const interna of internas) {
          expect(permitidas(rol, estado)).not.toContain(interna);
        }
      }
    }
  });
});

describe("transicionar() aplica esas reglas en el servidor", () => {
  function servicio(rol: Rol, estado: EstadoPedidoInterno) {
    const prisma = { $transaction: jest.fn() };
    const service = new CommerceLifecycleService(prisma as never);
    (service as any).access = {
      getActor: jest.fn().mockResolvedValue(actor(rol)),
      assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
    };
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(estado, { comprobanteUrl: "x" }));
    return { service, prisma };
  }

  test.each([
    [E.PAGADO, E.PENDIENTE_ENVIO],
    [E.PENDIENTE_ENVIO, E.ENVIADO],
    [E.PENDIENTE_PAGO, E.PAGADO],
  ])("un administrador que intenta pasar de %s a %s recibe 409", async (desde, hacia) => {
    const { service, prisma } = servicio(Rol.administrador, desde);

    await expect(
      service.transicionar("administrador-1", 41, { estadoDestino: hacia }),
    ).rejects.toMatchObject({ status: 409 });
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  test("un gerente si puede pasarlo a en preparacion", async () => {
    const { service, prisma } = servicio(Rol.gerente, E.PAGADO);
    prisma.$transaction.mockRejectedValue(new Error("llego a la transaccion"));

    await expect(
      service.transicionar("gerente-1", 41, { estadoDestino: E.PENDIENTE_ENVIO }),
    ).rejects.toThrow("llego a la transaccion");
  });
});

describe("avisos al cliente durante el envio", () => {
  function servicioConTransaccion(estadoInicial: EstadoPedidoInterno) {
    const tx: any = {
      pedidoApp: {
        findUnique: jest.fn(),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      pedidoAppEstadoHistorico: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = { $transaction: jest.fn(async (fn: (t: any) => unknown) => fn(tx)) };
    const service = new CommerceLifecycleService(prisma as never);
    (service as any).access = {
      getActor: jest.fn().mockResolvedValue(actor(Rol.gerente)),
      assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
    };
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(estadoInicial));
    jest.spyOn(service as any, "loadPedidoRecepcion").mockResolvedValue(pedido(estadoInicial));
    jest.spyOn(service as any, "getPedido").mockResolvedValue({ id: 41 });
    const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
    (service as any).notificaciones = { crearParaUsuarios };
    return { service, crearParaUsuarios };
  }

  test("al pasar a en preparacion se notifica a quien compro", async () => {
    const { service, crearParaUsuarios } = servicioConTransaccion(E.PAGADO);

    await service.transicionar("gerente-1", 41, { estadoDestino: E.PENDIENTE_ENVIO });

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({
        usuarioIds: ["admin-1"],
        tipo: "pedido_preparacion",
        referenciaTipo: "PedidoApp",
        referenciaId: 41,
      }),
    );
  });

  test("al pasar a en camino se notifica y se le pide confirmar la recepcion", async () => {
    const { service, crearParaUsuarios } = servicioConTransaccion(E.PENDIENTE_ENVIO);

    await service.transicionar("gerente-1", 41, { estadoDestino: E.ENVIADO });

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({
        tipo: "pedido_enviado",
        mensaje: expect.stringContaining("confirma que lo recibiste completo"),
      }),
    );
  });
});

describe("el estado de la app se refleja en WordPress", () => {
  const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

  function servicioConWoo(rol: Rol, estadoInicial: EstadoPedidoInterno, wooOrderId: string | null = "2395") {
    const tx: any = {
      pedidoApp: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
      pedidoAppEstadoHistorico: { create: jest.fn().mockResolvedValue({}) },
    };
    const prisma = { $transaction: jest.fn(async (fn: (t: any) => unknown) => fn(tx)) };
    const service = new CommerceLifecycleService(prisma as never);
    (service as any).access = {
      getActor: jest.fn().mockResolvedValue(actor(rol)),
      assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
    };
    const base = pedido(estadoInicial, { wooOrderId, comprobanteUrl: "https://drive.google.com/file/d/x/view" });
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(base);
    jest.spyOn(service as any, "loadPedidoRecepcion").mockResolvedValue(base);
    jest.spyOn(service as any, "getPedido").mockResolvedValue({ id: 41 });
    jest.spyOn(service as any, "applyInventory").mockResolvedValue(undefined);
    (service as any).points = { applyAccumulation: jest.fn().mockResolvedValue(undefined) };
    const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
    (service as any).notificaciones = { crearParaUsuarios };
    return { service, crearParaUsuarios };
  }

  const cambiosEnWoo = () =>
    woo.mock.calls
      .filter(([, init]) => (init as RequestInit | undefined)?.method === "PUT")
      .map(([url, init]) => ({ url, body: JSON.parse(String((init as RequestInit).body)) }));

  beforeEach(() => {
    woo.mockReset();
    woo.mockResolvedValue({});
  });

  test.each([
    [Rol.gerente, E.PENDIENTE_PAGO, E.PAGADO, "pago-manual"],
    [Rol.gerente, E.PAGADO, E.PENDIENTE_ENVIO, "en-preparacion"],
    [Rol.gerente, E.PENDIENTE_ENVIO, E.ENVIADO, "en-camino"],
    [Rol.administrador, E.ENVIADO, E.RECIBIDO, "entregado"],
    [Rol.administrador, E.RECIBIDO, E.ENTREGADO, "entregado"],
  ])("%s pasa %s -> %s en la app y WordPress queda en '%s'", async (rol, desde, hacia, estadoWoo) => {
    const { service } = servicioConWoo(rol, desde);

    await service.transicionar(`${rol}-1`, 41, { estadoDestino: hacia });

    expect(cambiosEnWoo()).toEqual([
      { url: "https://tienda.test/orders/2395", body: { status: estadoWoo } },
    ]);
  });

  test("cancelar en la app cancela el pedido en WordPress", async () => {
    const { service } = servicioConWoo(Rol.gerente, E.PAGADO);
    // Con comprobante no se puede cancelar desde la app; se prueba sin el.
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(
      pedido(E.PENDIENTE_PAGO, { wooOrderId: "2395" }),
    );
    jest.spyOn(service as any, "loadPedidoRecepcion").mockResolvedValue(
      pedido(E.PENDIENTE_PAGO, { wooOrderId: "2395" }),
    );

    await service.transicionar("gerente-1", 41, { estadoDestino: E.CANCELADO });

    expect(cambiosEnWoo()).toEqual([
      { url: "https://tienda.test/orders/2395", body: { status: "cancelled" } },
    ]);
  });

  test("un pedido sin id de WooCommerce no llama a la tienda", async () => {
    const { service } = servicioConWoo(Rol.gerente, E.PAGADO, null);
    await service.transicionar("gerente-1", 41, { estadoDestino: E.PENDIENTE_ENVIO });
    expect(woo).not.toHaveBeenCalled();
  });

  test("si WordPress no responde o rechaza el estado, el cambio en la app igual queda hecho", async () => {
    woo.mockRejectedValue(new Error("La tienda no pudo completar la solicitud"));
    const { service, crearParaUsuarios } = servicioConWoo(Rol.gerente, E.PAGADO);

    await expect(
      service.transicionar("gerente-1", 41, { estadoDestino: E.PENDIENTE_ENVIO }),
    ).resolves.toEqual({ id: 41 });
    expect(crearParaUsuarios).toHaveBeenCalledWith(expect.objectContaining({ tipo: "pedido_preparacion" }));
  });

  test("confirmar el pago desde la app tambien le avisa al cliente", async () => {
    const { service, crearParaUsuarios } = servicioConWoo(Rol.gerente, E.PENDIENTE_PAGO);

    await service.transicionar("gerente-1", 41, { estadoDestino: E.PAGADO });

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({ tipo: "pedido_pagado", usuarioIds: ["admin-1"] }),
    );
  });

  test("recibido y entregado no generan aviso: los confirma el propio cliente", async () => {
    const { service, crearParaUsuarios } = servicioConWoo(Rol.administrador, E.ENVIADO);
    await service.transicionar("administrador-1", 41, { estadoDestino: E.RECIBIDO });
    expect(crearParaUsuarios).not.toHaveBeenCalled();
  });
});

