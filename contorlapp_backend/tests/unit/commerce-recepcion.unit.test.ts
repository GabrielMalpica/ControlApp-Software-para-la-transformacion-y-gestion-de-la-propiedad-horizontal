import { EstadoPedidoInterno, Prisma, Rol, TipoPedidoApp } from "@prisma/client";

jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((_ns: string, ruta: string) => `https://tienda.test${ruta}`),
}));

import { CommerceLifecycleService } from "../../src/services/CommerceLifecycleService";

const E = EstadoPedidoInterno;
const D = (n: number) => new Prisma.Decimal(n);

const insumo = (id: number, nombre: string, unidad: string) => ({
  id,
  nombre,
  unidad,
  empresaId: "EMP-1",
  wooProductId: null,
  wooSku: null,
  wooFactorConversion: D(1),
});

const item = (id: number, nombre: string, cantidad: number, factor: number, ins: ReturnType<typeof insumo>) => ({
  id,
  pedidoId: 41,
  wooProductId: 100 + id,
  wooVariationId: null,
  nombreProducto: nombre,
  sku: null,
  cantidad: D(cantidad),
  wooFactorInventario: D(factor),
  insumoId: ins.id,
  insumo: ins,
});

const SANITABS = insumo(7, "Sanitabs", "pastilla");
const CLORO = insumo(8, "Cloro", "L");

function pedido(overrides: Record<string, unknown> = {}) {
  return {
    id: 41,
    tipo: TipoPedidoApp.CONJUNTO,
    estado: E.ENVIADO,
    usuarioId: "admin-1",
    conjuntoId: "CJ-1",
    conjunto: { nombre: "Los Pinos", empresaId: "EMP-1" },
    wooOrderId: "2395",
    total: D(50000),
    comprobanteUrl: "https://drive.google.com/file/d/x/view",
    entradaInventarioAplicada: false,
    items: [item(1, "Sanitabs (60)", 2, 60, SANITABS), item(2, "Cloro 4L", 3, 4, CLORO)],
    ...overrides,
  };
}

const actor = (rol: Rol) => ({ id: `${rol}-1`, nombre: `Persona ${rol}`, rol, empresaId: "EMP-1", residente: null });

function servicio(rol: Rol, pedidoBase = pedido()) {
  const inventarioIncrementos: Array<{ insumoId: number; cantidad: string }> = [];
  const consumos: Array<{ insumoId: number; cantidad: string }> = [];
  const itemsActualizados: Array<{ id: number; data: any }> = [];

  const tx: any = {
    pedidoApp: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    pedidoAppEstadoHistorico: { create: jest.fn().mockResolvedValue({}) },
    pedidoAppItem: {
      update: jest.fn(async (arg: any) => {
        itemsActualizados.push({ id: arg.where.id, data: arg.data });
        return {};
      }),
    },
    inventario: { upsert: jest.fn().mockResolvedValue({ id: 900 }) },
    inventarioInsumo: {
      upsert: jest.fn(async (arg: any) => {
        inventarioIncrementos.push({ insumoId: arg.where.inventarioId_insumoId.insumoId, cantidad: String(arg.create.cantidad) });
        return {};
      }),
    },
    consumoInsumo: {
      upsert: jest.fn(async (arg: any) => {
        consumos.push({ insumoId: arg.create.insumoId, cantidad: String(arg.create.cantidad) });
        return {};
      }),
    },
    insumo: { findFirst: jest.fn().mockResolvedValue(null) },
  };
  const prisma: any = {
    $transaction: jest.fn(async (fn: (t: any) => unknown) => fn(tx)),
    gerente: { findMany: jest.fn().mockResolvedValue([{ id: "gerente-1" }]) },
    jefeOperaciones: { findMany: jest.fn().mockResolvedValue([{ id: "jefe-1" }, { id: "jefe-2" }]) },
    insumo: { findMany: jest.fn().mockResolvedValue([]), findFirst: jest.fn().mockResolvedValue(null) },
  };
  const service = new CommerceLifecycleService(prisma);
  (service as any).access = {
    getActor: jest.fn().mockResolvedValue(actor(rol)),
    assertPedidoAccess: jest.fn().mockResolvedValue(undefined),
    assertConjuntoAccess: jest.fn().mockResolvedValue(undefined),
    esRolOperativo: jest.fn(() => ([Rol.administrador, Rol.gerente, Rol.jefe_operaciones] as Rol[]).includes(rol)),
  };
  jest.spyOn(service as any, "loadPedido").mockResolvedValue(pedidoBase);
  jest.spyOn(service as any, "loadPedidoRecepcion").mockResolvedValue(pedidoBase);
  jest.spyOn(service as any, "getPedido").mockResolvedValue({ id: 41 });
  const crearParaUsuarios = jest.fn().mockResolvedValue(undefined);
  (service as any).notificaciones = { crearParaUsuarios };
  const points = { applyAccumulation: jest.fn() };
  (service as any).points = points;
  const nota = jest.spyOn(service as any, "pushWooOrderNote").mockResolvedValue(undefined);
  const reflejar = jest.spyOn(service as any, "reflejarEstadoEnWoo").mockResolvedValue(undefined);
  return { service, tx, prisma, inventarioIncrementos, consumos, itemsActualizados, crearParaUsuarios, nota, points, reflejar };
}

const recibir = (s: ReturnType<typeof servicio>, recepcion?: unknown, rol: Rol = Rol.administrador) =>
  s.service.transicionar(`${rol}-1`, 41, { estadoDestino: E.RECIBIDO, ...(recepcion ? { recepcion } : {}) });

describe("recepcion: reportar lo que llego", () => {
  test("sin reporte: todo llego completo y se suma lo pedido x su factor", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    // 2 x 60 = 120 pastillas y 3 x 4 = 12 L
    expect(s.inventarioIncrementos).toEqual([
      { insumoId: 7, cantidad: "120" },
      { insumoId: 8, cantidad: "12" },
    ]);
    expect(s.crearParaUsuarios).not.toHaveBeenCalled();
  });

  test("llego incompleto: solo lo recibido suma al inventario (1 de 2 Sanitabs = 60 pastillas)", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 1, cantidadRecibida: 1, nota: "Una caja llego rota" }]);

    expect(s.inventarioIncrementos).toEqual([
      { insumoId: 7, cantidad: "60" },
      { insumoId: 8, cantidad: "12" },
    ]);
  });

  test("lo que no llego (0) no genera movimiento de inventario", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 2, cantidadRecibida: 0 }]);

    expect(s.inventarioIncrementos).toEqual([{ insumoId: 7, cantidad: "120" }]);
    expect(s.consumos.map((c) => c.insumoId)).toEqual([7]);
  });

  test("queda registrado por producto cuanto llego y la nota", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 1, cantidadRecibida: 1, nota: "Una caja llego rota" }]);

    expect(s.itemsActualizados).toEqual([
      { id: 1, data: { cantidadRecibida: D(1), novedadRecepcion: "Una caja llego rota" } },
      { id: 2, data: { cantidadRecibida: D(3), novedadRecepcion: null } },
    ]);
  });

  test("con novedades: se avisa a gerentes y jefes de la empresa y se anota en WooCommerce", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 1, cantidadRecibida: 1, nota: "Una caja llego rota" }]);

    const aviso = s.crearParaUsuarios.mock.calls.map(([d]) => d).find((d) => d.tipo === "pedido_novedad_recepcion");
    expect(aviso).toMatchObject({
      usuarioIds: ["gerente-1", "jefe-1", "jefe-2"],
      referenciaTipo: "PedidoApp",
      referenciaId: 41,
    });
    expect(aviso.mensaje).toContain("Los Pinos");
    expect(aviso.mensaje).toContain("Sanitabs (60): llegaron 1 de 2 (Una caja llego rota)");
    expect(s.nota).toHaveBeenCalledWith("2395", expect.stringContaining("Recepción con novedades reportada por Persona administrador"));
  });

  test("el historial del pedido deja constancia de la novedad", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 2, cantidadRecibida: 1 }]);

    expect(s.tx.pedidoAppEstadoHistorico.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        estadoNuevo: E.RECIBIDO,
        motivo: expect.stringContaining("Recepción con novedades: Cloro 4L: llegaron 1 de 3"),
      }),
    });
  });

  test("si el aviso a Control SAS falla, la recepcion igual queda hecha", async () => {
    const s = servicio(Rol.administrador);
    s.prisma.gerente.findMany.mockRejectedValue(new Error("db caida"));
    const errores = jest.spyOn(console, "error").mockImplementation(() => undefined);

    await expect(recibir(s, [{ itemId: 1, cantidadRecibida: 0 }])).resolves.toEqual({ id: 41 });
    expect(s.inventarioIncrementos.length).toBeGreaterThan(0);
    errores.mockRestore();
  });

  test("no se puede recibir mas de lo pedido", async () => {
    const s = servicio(Rol.administrador);

    await expect(recibir(s, [{ itemId: 1, cantidadRecibida: 5 }])).rejects.toMatchObject({ status: 400 });
    expect(s.prisma.$transaction).not.toHaveBeenCalled();
  });

  test("un producto que no es del pedido se rechaza", async () => {
    const s = servicio(Rol.administrador);

    await expect(recibir(s, [{ itemId: 999, cantidadRecibida: 1 }])).rejects.toMatchObject({ status: 400 });
    expect(s.prisma.$transaction).not.toHaveBeenCalled();
  });

  test("cantidades negativas o mensajes enormes no pasan la validacion", async () => {
    const s = servicio(Rol.administrador);

    await expect(recibir(s, [{ itemId: 1, cantidadRecibida: -1 }])).rejects.toBeDefined();
    await expect(recibir(s, [{ itemId: 1, cantidadRecibida: 1, nota: "x".repeat(301) }])).rejects.toBeDefined();
  });

  test("un pedido de residente ignora el reporte (no maneja inventario)", async () => {
    const s = servicio(Rol.residente, pedido({ tipo: TipoPedidoApp.RESIDENTE, conjunto: null }));

    await recibir(s, [{ itemId: 1, cantidadRecibida: 0 }], Rol.residente);

    expect(s.tx.pedidoAppItem.update).not.toHaveBeenCalled();
    expect(s.crearParaUsuarios.mock.calls.some(([d]) => d.tipo === "pedido_novedad_recepcion")).toBe(false);
  });
});

describe("recepcion: recibir cierra el pedido como entregado", () => {
  const pasosDeEstado = (s: ReturnType<typeof servicio>) =>
    // Solo los cambios de estado (la marca de inventario aplicado no cuenta).
    s.tx.pedidoApp.updateMany.mock.calls
      .filter(([arg]: any) => arg.data.estado !== undefined)
      .map(([arg]: any) => [arg.where.estado, arg.data.estado]);
  const historial = (s: ReturnType<typeof servicio>) =>
    s.tx.pedidoAppEstadoHistorico.create.mock.calls.map(([{ data }]: any) => [data.estadoAnterior, data.estadoNuevo]);

  test("confirmar la recepcion deja el pedido ENTREGADO, sin pedir un segundo paso", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    expect(pasosDeEstado(s)).toEqual([
      [E.ENVIADO, E.RECIBIDO],
      [E.RECIBIDO, E.ENTREGADO],
    ]);
  });

  test("en el historial quedan los dos pasos, y el segundo dice que fue automatico", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    expect(historial(s)).toEqual([
      [E.ENVIADO, E.RECIBIDO],
      [E.RECIBIDO, E.ENTREGADO],
    ]);
    const segundo = s.tx.pedidoAppEstadoHistorico.create.mock.calls[1][0].data;
    expect(segundo.motivo).toBe("Entregado automáticamente al confirmar la recepción");
  });

  test("WordPress queda en 'entregado' (no en 'recibido') y con una nota para el equipo", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    expect(s.reflejar).toHaveBeenCalledTimes(1);
    expect(s.reflejar).toHaveBeenCalledWith("2395", E.ENTREGADO);
    expect(s.nota).toHaveBeenCalledWith(
      "2395",
      expect.stringContaining("Recepción confirmada por Persona administrador: el pedido llegó completo y quedó entregado"),
    );
  });

  test("con novedades: WordPress igual queda en 'entregado' y la nota es la de la novedad (no se duplica)", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s, [{ itemId: 1, cantidadRecibida: 1 }]);

    expect(s.reflejar).toHaveBeenCalledWith("2395", E.ENTREGADO);
    const notas = s.nota.mock.calls.map(([, texto]: any) => String(texto));
    expect(notas).toHaveLength(1);
    expect(notas[0]).toContain("Recepción con novedades");
  });

  test("los puntos se acumulan: la entrega cuenta como verificada porque paso por la recepcion", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    expect(s.points.applyAccumulation).toHaveBeenCalledTimes(1);
    expect(s.points.applyAccumulation).toHaveBeenCalledWith(
      s.tx,
      expect.objectContaining({ estado: E.ENTREGADO, entregaVerificada: true }),
    );
  });

  test("el inventario se suma una sola vez aunque el pedido pase por dos estados", async () => {
    const s = servicio(Rol.administrador);

    await recibir(s);

    expect(s.inventarioIncrementos).toHaveLength(2);
  });

  test("si el segundo paso pierde la carrera, no queda nada a medias (error 409)", async () => {
    const s = servicio(Rol.administrador);
    s.tx.pedidoApp.updateMany
      .mockResolvedValueOnce({ count: 1 }) // marca de inventario aplicado
      .mockResolvedValueOnce({ count: 1 }) // ENVIADO -> RECIBIDO
      .mockResolvedValueOnce({ count: 0 }); // RECIBIDO -> ENTREGADO: alguien ya lo movio

    await expect(recibir(s)).rejects.toMatchObject({ status: 409 });
  });

  test("un pedido de residente tambien queda entregado al confirmar que lo recibio", async () => {
    const s = servicio(Rol.residente, pedido({ tipo: TipoPedidoApp.RESIDENTE, conjunto: null }));

    await recibir(s, undefined, Rol.residente);

    expect(pasosDeEstado(s)).toEqual([
      [E.ENVIADO, E.RECIBIDO],
      [E.RECIBIDO, E.ENTREGADO],
    ]);
    expect(s.reflejar).toHaveBeenCalledWith("2395", E.ENTREGADO);
  });

  test("un pedido que quedo en RECIBIDO (de antes) todavia puede cerrarse como entregado", async () => {
    const s = servicio(Rol.administrador, pedido({ estado: E.RECIBIDO }));

    await s.service.transicionar("administrador-1", 41, { estadoDestino: E.ENTREGADO });

    expect(pasosDeEstado(s)).toEqual([[E.RECIBIDO, E.ENTREGADO]]);
    expect(s.points.applyAccumulation).toHaveBeenCalledWith(
      s.tx,
      expect.objectContaining({ entregaVerificada: true }),
    );
  });

  test("otras transiciones no se encadenan (en camino solo pasa a en camino)", async () => {
    const s = servicio(Rol.gerente, pedido({ estado: E.PENDIENTE_ENVIO }));

    await s.service.transicionar("gerente-1", 41, { estadoDestino: E.ENVIADO });

    expect(pasosDeEstado(s)).toEqual([[E.PENDIENTE_ENVIO, E.ENVIADO]]);
  });
});

describe("recepcion: el detalle de los insumos es fijo para quien compra", () => {
  test("vista previa: el administrador del conjunto NO puede mapear ni editar", async () => {
    const s = servicio(Rol.administrador);
    const preview: any = await s.service.previewRecepcion("administrador-1", 41);
    expect(preview.puedeMapear).toBe(false);
  });

  test.each([Rol.gerente, Rol.jefe_operaciones])("vista previa: %s si puede configurar insumos", async (rol) => {
    const s = servicio(rol);
    const preview: any = await s.service.previewRecepcion(`${rol}-1`, 41);
    expect(preview.puedeMapear).toBe(true);
  });

  test("con un producto sin configurar, el administrador recibe un mensaje claro (no 'mapea')", async () => {
    const sinInsumo = pedido({ items: [{ ...item(1, "Producto raro", 1, 1, SANITABS), insumoId: null, insumo: null }] });
    const s = servicio(Rol.administrador, sinInsumo);
    jest.spyOn(s.service as any, "autoCrearInsumoDesdeWoo").mockResolvedValue(null);

    const preview: any = await s.service.previewRecepcion("administrador-1", 41);

    expect(preview.puedeAplicar).toBe(false);
    expect(preview.mensaje).toContain("Avisa a Control SAS");
    expect(preview.mensaje).not.toContain("Mapea");
  });

  test("con todo configurado, el mensaje invita a revisar lo que llego", async () => {
    const s = servicio(Rol.administrador);
    const preview: any = await s.service.previewRecepcion("administrador-1", 41);
    expect(preview.mensaje).toContain("Solo lo que marques como recibido");
  });

  test.each([Rol.administrador, Rol.residente])("%s no puede mapear un producto a otro insumo (403)", async (rol) => {
    const s = servicio(rol);
    await expect(
      s.service.mapearItem(`${rol}-1`, 41, 1, { insumoId: 8, factorConversion: 99 }),
    ).rejects.toMatchObject({ status: 403 });
    expect(s.prisma.$transaction).not.toHaveBeenCalled();
  });

  test("el equipo interno si puede mapear", async () => {
    const s = servicio(Rol.gerente);
    s.prisma.$transaction.mockRejectedValue(new Error("llego a la transaccion"));
    await expect(s.service.mapearItem("gerente-1", 41, 1, { insumoId: 8 })).rejects.toThrow("llego a la transaccion");
  });

  test("el detalle del pedido expone lo recibido y la novedad por producto", () => {
    const s = servicio(Rol.administrador);
    const conReporte = pedido({
      items: [
        { ...item(1, "Sanitabs (60)", 2, 60, SANITABS), cantidadRecibida: D(1), novedadRecepcion: "Una caja rota" },
      ],
    });
    const json = (s.service as any).serializePedido(actor(Rol.administrador), {
      ...conReporte,
      historialEstados: [],
      consumosInventario: [],
      pagarAhora: D(0),
      descuentoPuntos: D(0),
    });
    expect(json.items[0]).toMatchObject({ cantidad: 2, cantidadRecibida: 1, novedadRecepcion: "Una caja rota" });
  });
});
