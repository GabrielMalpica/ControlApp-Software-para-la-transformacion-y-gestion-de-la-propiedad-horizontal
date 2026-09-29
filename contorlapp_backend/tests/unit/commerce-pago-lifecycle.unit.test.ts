import { CanalPago, EstadoCobro, EstadoPedidoInterno, Prisma, Rol, TipoPedidoApp } from "@prisma/client";

jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));

const crearCobro = jest.fn();
const verificarCobro = jest.fn();
jest.mock("../../src/services/pagos/pagoServiceInstance", () => ({
  pagoService: {
    crearCobro: (...args: unknown[]) => crearCobro(...args),
    verificarCobro: (...args: unknown[]) => verificarCobro(...args),
  },
}));

import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";
import { PedidoNoConfirmableError } from "../../src/services/pagos/errors";
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
    pagarAhora: new Prisma.Decimal(0),
    comprobanteUrl: null,
    items: [],
    ...overrides,
  };
}

const actor = {
  id: "admin-1",
  nombre: "Un administrador",
  rol: Rol.administrador,
  empresaId: null,
  residente: null,
};

function cobro(overrides: Record<string, unknown> = {}) {
  return {
    id: 7,
    proveedor: "factus",
    referenceCode: "CA-abc",
    canal: CanalPago.CONTROLAPP,
    pedidoAppId: 41,
    wooOrderId: null,
    usuarioId: "admin-1",
    montoEsperado: new Prisma.Decimal(50000),
    montoProveedor: null,
    moneda: "COP",
    estado: EstadoCobro.PENDIENTE,
    estadoProveedor: "ready",
    qrBase64: "x",
    expiraLocalEn: new Date(Date.now() + 60_000),
    proximaVerificacion: new Date(Date.now() + 10_000),
    intentosVerificacion: 1,
    lockedUntil: null,
    pagadoDetectadoEn: null,
    pendienteSincronizarWoo: false,
    creadoEn: new Date(),
    actualizadoEn: new Date(),
    ...overrides,
  };
}

beforeEach(() => {
  crearCobro.mockReset();
  verificarCobro.mockReset();
  jest.clearAllMocks();
});

describe("confirmarPagoSistema (confirmador registrado en PagoService)", () => {
  function contexto(overrides: Record<string, unknown> = {}) {
    return {
      cobroId: 7,
      pedidoAppId: 41,
      wooOrderId: null,
      usuarioId: "admin-1",
      montoEsperado: new Prisma.Decimal(50000),
      referenceCode: "CA-abc",
      ...overrides,
    };
  }

  test("sin pedidoAppId no hay nada que confirmar", async () => {
    const service = new CommerceLifecycleService({} as never);
    const tx: any = {};

    await expect(service.confirmarPagoSistema(tx, contexto({ pedidoAppId: null }))).rejects.toThrow(
      PedidoNoConfirmableError,
    );
  });

  test("pedido inexistente", async () => {
    const service = new CommerceLifecycleService({} as never);
    const tx: any = { pedidoApp: { findUnique: jest.fn().mockResolvedValue(null) } };

    await expect(service.confirmarPagoSistema(tx, contexto())).rejects.toThrow(PedidoNoConfirmableError);
  });

  test("pedido que ya no esta PENDIENTE_PAGO (cancelado, o ya pagado por otra via)", async () => {
    const service = new CommerceLifecycleService({} as never);
    const tx: any = {
      pedidoApp: {
        findUnique: jest.fn().mockResolvedValue({ id: 41, estado: E.CANCELADO, usuarioId: "admin-1", wooOrderId: null }),
      },
    };

    await expect(service.confirmarPagoSistema(tx, contexto())).rejects.toThrow(PedidoNoConfirmableError);
  });

  test("carrera: otra transaccion ya movio el pedido antes del claim", async () => {
    const service = new CommerceLifecycleService({} as never);
    const tx: any = {
      pedidoApp: {
        findUnique: jest.fn().mockResolvedValue({ id: 41, estado: E.PENDIENTE_PAGO, usuarioId: "admin-1", wooOrderId: null }),
        updateMany: jest.fn().mockResolvedValue({ count: 0 }),
      },
    };

    await expect(service.confirmarPagoSistema(tx, contexto())).rejects.toThrow(PedidoNoConfirmableError);
  });

  test("camino feliz: mueve el pedido a PAGADO y deja historial con actor factus", async () => {
    const service = new CommerceLifecycleService({} as never);
    const historial = jest.fn().mockResolvedValue({});
    const tx: any = {
      pedidoApp: {
        findUnique: jest.fn().mockResolvedValue({ id: 41, estado: E.PENDIENTE_PAGO, usuarioId: "admin-1", wooOrderId: "2395" }),
        updateMany: jest.fn().mockResolvedValue({ count: 1 }),
      },
      pedidoAppEstadoHistorico: { create: historial },
    };

    await service.confirmarPagoSistema(tx, contexto());

    expect(tx.pedidoApp.updateMany).toHaveBeenCalledWith({
      where: { id: 41, estado: E.PENDIENTE_PAGO },
      data: { estado: E.PAGADO },
    });
    expect(historial).toHaveBeenCalledWith({
      data: expect.objectContaining({
        pedidoId: 41,
        estadoAnterior: E.PENDIENTE_PAGO,
        estadoNuevo: E.PAGADO,
        cambiadoPorId: "admin-1",
        cambiadoPorRol: "factus",
        motivo: expect.stringContaining("CA-abc"),
      }),
    });
  });
});

describe("crearPago / obtenerPago / verificarPago", () => {
  function servicio(prismaOverrides: Record<string, unknown> = {}) {
    const prisma: any = { pagoCobro: { findFirst: jest.fn() }, ...prismaOverrides };
    const service = new CommerceLifecycleService(prisma as never);
    (service as any).access = {
      getActor: jest.fn().mockResolvedValue(actor),
      assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
    };
    return { service, prisma };
  }

  test("crearPago exige que el pedido este pendiente de pago", async () => {
    const { service } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PAGADO));

    await expect(service.crearPago("admin-1", 41)).rejects.toMatchObject({ status: 409 });
    expect(crearCobro).not.toHaveBeenCalled();
  });

  test("crearPago cobra pagarAhora cuando es mayor que cero (pedidos de servicio)", async () => {
    const { service } = servicio();
    jest
      .spyOn(service as any, "loadPedido")
      .mockResolvedValue(pedido(E.PENDIENTE_PAGO, { pagarAhora: new Prisma.Decimal(35000), total: new Prisma.Decimal(70000) }));
    crearCobro.mockResolvedValue(cobro({ montoEsperado: new Prisma.Decimal(35000) }));

    await service.crearPago("admin-1", 41);

    expect(crearCobro).toHaveBeenCalledWith(
      expect.objectContaining({ canal: CanalPago.CONTROLAPP, montoEsperado: 35000, pedidoAppId: 41, usuarioId: "admin-1" }),
    );
  });

  test("crearPago cobra el total cuando no hay pagarAhora", async () => {
    const { service } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO, { total: new Prisma.Decimal(50000) }));
    crearCobro.mockResolvedValue(cobro());

    await service.crearPago("admin-1", 41);

    expect(crearCobro).toHaveBeenCalledWith(expect.objectContaining({ montoEsperado: 50000 }));
  });

  test("crearPago devuelve el cobro serializado (sin exponer campos internos)", async () => {
    const { service } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO));
    crearCobro.mockResolvedValue(cobro());

    const resultado = await service.crearPago("admin-1", 41);

    expect(resultado).toMatchObject({ id: 7, referenceCode: "CA-abc", estado: EstadoCobro.PENDIENTE, qrBase64: "x" });
  });

  test("obtenerPago devuelve null si nunca se genero un cobro", async () => {
    const { service, prisma } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO));
    prisma.pagoCobro.findFirst.mockResolvedValue(null);

    await expect(service.obtenerPago("admin-1", 41)).resolves.toBeNull();
  });

  test("obtenerPago devuelve el ultimo cobro", async () => {
    const { service, prisma } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO));
    prisma.pagoCobro.findFirst.mockResolvedValue(cobro());

    await expect(service.obtenerPago("admin-1", 41)).resolves.toMatchObject({ id: 7 });
    expect(prisma.pagoCobro.findFirst).toHaveBeenCalledWith({
      where: { pedidoAppId: 41 },
      orderBy: { creadoEn: "desc" },
    });
  });

  test("verificarPago falla si el pedido no tiene ningun cobro", async () => {
    const { service, prisma } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO));
    prisma.pagoCobro.findFirst.mockResolvedValue(null);

    await expect(service.verificarPago("admin-1", 41)).rejects.toMatchObject({ status: 404 });
    expect(verificarCobro).not.toHaveBeenCalled();
  });

  test("verificarPago fuerza la consulta del ultimo cobro", async () => {
    const { service, prisma } = servicio();
    jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedido(E.PENDIENTE_PAGO));
    prisma.pagoCobro.findFirst.mockResolvedValue(cobro());
    verificarCobro.mockResolvedValue(cobro({ estado: EstadoCobro.PAGADO }));

    const resultado = await service.verificarPago("admin-1", 41);

    expect(verificarCobro).toHaveBeenCalledWith(7);
    expect(resultado.estado).toBe(EstadoCobro.PAGADO);
  });
});

describe("avisos posteriores a la confirmacion del pago", () => {
  const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

  function servicio() {
    const prisma: any = { pedidoApp: { findUnique: jest.fn() } };
    const service = new CommerceLifecycleService(prisma as never);
    const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
    (service as any).notificaciones = { crearParaUsuarios };
    return { service, prisma, crearParaUsuarios };
  }

  test("avisarPagoConfirmadoPorFactus no hace nada para un cobro sin pedido de ControlApp", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();

    await service.avisarPagoConfirmadoPorFactus(cobro({ pedidoAppId: null }) as never);

    expect(prisma.pedidoApp.findUnique).not.toHaveBeenCalled();
    expect(crearParaUsuarios).not.toHaveBeenCalled();
  });

  test("avisarPagoConfirmadoPorFactus notifica al cliente y refleja el pago en Woo", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ usuarioId: "admin-1", wooOrderId: "2395" });
    woo.mockResolvedValue({});

    await service.avisarPagoConfirmadoPorFactus(cobro() as never);

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({ usuarioIds: ["admin-1"], tipo: "pedido_pagado", referenciaId: 41 }),
    );
    // Primera llamada: PUT con el pago confirmado. Segunda: la nota interna.
    expect(woo.mock.calls[0][1]).toMatchObject({
      method: "PUT",
      body: JSON.stringify({ status: "processing", set_paid: true, transaction_id: "CA-abc" }),
    });
  });

  test("si Woo falla, el error se propaga (para que PagoService lo reintente) pero ya se notifico al cliente", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ usuarioId: "admin-1", wooOrderId: "2395" });
    woo.mockRejectedValue(new Error("Woo no responde"));

    await expect(service.avisarPagoConfirmadoPorFactus(cobro() as never)).rejects.toThrow("Woo no responde");
    expect(crearParaUsuarios).toHaveBeenCalled();
  });

  test("en un reintento (pendienteSincronizarWoo=true) no se vuelve a notificar, solo se reintenta Woo", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ usuarioId: "admin-1", wooOrderId: "2395" });
    woo.mockResolvedValue({});

    await service.avisarPagoConfirmadoPorFactus(cobro({ pendienteSincronizarWoo: true }) as never);

    expect(crearParaUsuarios).not.toHaveBeenCalled();
    expect(woo.mock.calls[0][1]).toMatchObject({ method: "PUT" });
  });

  test("avisarPagoFallidoPorFactus no hace nada para un cobro sin pedido de ControlApp", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();

    await service.avisarPagoFallidoPorFactus(cobro({ pedidoAppId: null }) as never);

    expect(prisma.pedidoApp.findUnique).not.toHaveBeenCalled();
    expect(crearParaUsuarios).not.toHaveBeenCalled();
  });

  test("avisarPagoFallidoPorFactus notifica al cliente y marca la orden failed en Woo", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({
      estado: E.PENDIENTE_PAGO,
      usuarioId: "admin-1",
      wooOrderId: "2395",
    });
    woo.mockResolvedValue({});

    await service.avisarPagoFallidoPorFactus(cobro() as never);

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({ usuarioIds: ["admin-1"], tipo: "pedido_pago_fallido", referenciaId: 41 }),
    );
    expect(woo.mock.calls[0][1]).toMatchObject({ method: "PUT", body: JSON.stringify({ status: "failed" }) });
  });

  test("avisarPagoFallidoPorFactus no toca nada si el pedido ya no esta pendiente de pago", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({
      estado: E.PAGADO,
      usuarioId: "admin-1",
      wooOrderId: "2395",
    });

    await service.avisarPagoFallidoPorFactus(cobro() as never);

    expect(crearParaUsuarios).not.toHaveBeenCalled();
    expect(woo).not.toHaveBeenCalled();
  });

  test("avisarPagoFallidoPorFactus es best-effort: si Woo falla, no revienta", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({
      estado: E.PENDIENTE_PAGO,
      usuarioId: "admin-1",
      wooOrderId: "2395",
    });
    woo.mockRejectedValue(new Error("Woo no responde"));

    await expect(service.avisarPagoFallidoPorFactus(cobro() as never)).resolves.toBeUndefined();
    expect(crearParaUsuarios).toHaveBeenCalled();
  });
});

describe("alertarAccionManualPago (huerfano / duplicado / discrepancia)", () => {
  function servicio() {
    const prisma: any = {
      pedidoApp: { findUnique: jest.fn() },
      gerente: { findMany: jest.fn().mockResolvedValue([{ id: "ger-1" }]) },
      jefeOperaciones: { findMany: jest.fn().mockResolvedValue([{ id: "jefe-1" }]) },
    };
    const service = new CommerceLifecycleService(prisma as never);
    const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
    (service as any).notificaciones = { crearParaUsuarios };
    return { service, prisma, crearParaUsuarios };
  }

  test("sin empresa asociada no notifica a nadie", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ conjunto: null });

    await service.alertarAccionManualPago(cobro() as never, "el pedido esta cancelado");

    expect(crearParaUsuarios).not.toHaveBeenCalled();
  });

  test("avisa a gerentes y jefes de la empresa del conjunto", async () => {
    const { service, prisma, crearParaUsuarios } = servicio();
    prisma.pedidoApp.findUnique.mockResolvedValue({ conjunto: { empresaId: "EMP-1" } });

    await service.alertarAccionManualPago(cobro() as never, "el pedido esta cancelado");

    expect(crearParaUsuarios).toHaveBeenCalledWith(
      expect.objectContaining({
        usuarioIds: ["ger-1", "jefe-1"],
        tipo: "pago_requiere_accion",
        mensaje: "el pedido esta cancelado",
        referenciaTipo: "PedidoApp",
        referenciaId: 41,
      }),
    );
  });
});
