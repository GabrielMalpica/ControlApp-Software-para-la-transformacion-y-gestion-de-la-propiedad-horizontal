import { CanalPago, EstadoSaldoServicio, Prisma } from "@prisma/client";

jest.mock("../../src/services/wooFetch", () => ({
  wooFetch: jest.fn(),
  buildWooUrl: jest.fn((ns: string, ruta: string) => `https://tienda.test/${ns}${ruta}`),
}));

import {
  SaldoServicioService,
  asegurarSinMora,
  calcularSaldoOrden,
  normalizarCorreo,
  normalizarTelefono,
  serviciosTerminados,
} from "../../src/services/pagos/SaldoServicioService";
import { PedidoNoConfirmableError } from "../../src/services/pagos/errors";
import { wooFetch } from "../../src/services/wooFetch";

const woo = wooFetch as jest.MockedFunction<typeof wooFetch>;

type Fila = Record<string, any>;

function coincide(fila: Fila, where: Fila = {}): boolean {
  return Object.entries(where).every(([campo, cond]) => {
    if (campo === "OR") return (cond as Fila[]).some((w) => coincide(fila, w));
    if (campo === "AND") return (cond as Fila[]).every((w) => coincide(fila, w));
    if (cond && typeof cond === "object" && !(cond instanceof Date) && !(cond instanceof Prisma.Decimal)) {
      if ("in" in cond) return cond.in.includes(fila[campo]);
      if ("contains" in cond) return String(fila[campo] ?? "").toLowerCase().includes(String(cond.contains).toLowerCase());
    }
    return fila[campo] === cond;
  });
}

function fakePrisma(inicial: { usuarios?: Fila[]; pedidos?: Fila[] } = {}) {
  const saldos: Fila[] = [];
  const incidencias: Fila[] = [];
  const cobros: Fila[] = [];
  const usuarios = inicial.usuarios ?? [];
  const pedidos = inicial.pedidos ?? [];
  const tabla = (filas: Fila[]) => ({
    findUnique: jest.fn(async ({ where }: Fila) => filas.find((f) => coincide(f, where)) ?? null),
    findUniqueOrThrow: jest.fn(async ({ where }: Fila) => {
      const f = filas.find((x) => coincide(x, where));
      if (!f) throw new Error("no existe");
      return f;
    }),
    findFirst: jest.fn(async ({ where }: Fila) => filas.filter((f) => coincide(f, where)).slice(-1)[0] ?? null),
    findMany: jest.fn(async ({ where }: Fila = {}) => filas.filter((f) => coincide(f, where))),
  });
  const prisma: any = {
    saldoServicio: {
      ...tabla(saldos),
      create: jest.fn(async ({ data }: Fila) => {
        if (saldos.some((s) => s.wooOrderId === data.wooOrderId)) {
          throw new Prisma.PrismaClientKnownRequestError("unico", { code: "P2002", clientVersion: "test" });
        }
        const fila = { id: saldos.length + 1, estado: EstadoSaldoServicio.PENDIENTE, ...data };
        saldos.push(fila);
        return fila;
      }),
      update: jest.fn(async ({ where, data }: Fila) => Object.assign(saldos.find((s) => s.id === where.id)!, data)),
      updateMany: jest.fn(async ({ where, data }: Fila) => {
        const filas = saldos.filter((s) => coincide(s, where));
        filas.forEach((s) => Object.assign(s, data));
        return { count: filas.length };
      }),
    },
    saldoServicioIncidencia: {
      createMany: jest.fn(async ({ data }: Fila) => {
        incidencias.push(...data);
        return { count: data.length };
      }),
    },
    pedidoApp: tabla(pedidos),
    usuario: tabla(usuarios),
    pagoCobro: {
      ...tabla(cobros),
      updateMany: jest.fn(async () => ({ count: 1 })),
    },
  };
  return { prisma, saldos, incidencias, cobros };
}

function servicio(inicial?: Parameters<typeof fakePrisma>[0]) {
  const db = fakePrisma(inicial);
  const pagos = {
    crearCobro: jest.fn(async (input: Fila) => ({ id: 50, referenceCode: "SA-1", estado: "PENDIENTE", ...input })),
    verificarCobro: jest.fn(),
  };
  const avisos = {
    notificarUsuario: jest.fn().mockResolvedValue(1),
    alertarEquipo: jest.fn().mockResolvedValue(undefined),
  };
  return { ...db, pagos, avisos, service: new SaldoServicioService(db.prisma, pagos as any, avisos) };
}

const ordenServicio = (over: Fila = {}) => ({
  id: 2434,
  status: "processing",
  total: "71000.00",
  order_key: "wc_order_clave",
  payment_method: "controlapp_factus",
  billing: {
    first_name: "Martin",
    last_name: "Hidalgo",
    email: "Martin@Correo.COM ",
    phone: "+57 320 826 2940",
    address_1: "Carrera 6 # 3-58",
    city: "Villavicencio",
    state: "Meta",
  },
  meta_data: [
    { key: "_clsr_pay_choice", value: "deposit" },
    { key: "_clsr_pay_now", value: "36000" },
  ],
  line_items: [
    { name: "Detergente", meta_data: [] },
    { name: "Revision de dano", meta_data: [{ key: "Fecha del servicio", value: "2026-10-22" }, { key: "Pago", value: "Anticipo" }] },
  ],
  ...over,
});

/** wooFetch: la orden y luego las reservas del marketplace. */
function tienda(orden: Fila, reservas: Fila[] = [{ estado: "completada" }]) {
  woo.mockImplementation(async (url: string) => (String(url).includes("/clmk/") ? reservas : orden) as any);
}

beforeEach(() => woo.mockReset());

describe("reglas puras del saldo", () => {
  test("servicio con anticipo pagado: queda el total menos el anticipo", () => {
    expect(calcularSaldoOrden(ordenServicio())).toEqual({ saldo: 35000, pagadoAntes: 36000, total: 71000 });
  });

  test.each([
    ["solo productos (deposit es el valor por defecto)", { line_items: [{ name: "Detergente", meta_data: [] }] }],
    ["servicio al 100 %", { line_items: [{ meta_data: [{ key: "Pago", value: "100%" }] }] }],
    ["orden sin pagar", { status: "pending" }],
    ["orden cancelada", { status: "cancelled" }],
    ["contra reembolso (se cobra todo en el sitio)", { payment_method: "cod" }],
    ["credito del conjunto (fin de mes)", { payment_method: "conjunto_credito" }],
  ])("sin saldo: %s", (_caso, over) => {
    expect(calcularSaldoOrden(ordenServicio(over))).toMatchObject({ saldo: 0 });
  });

  test("el servicio termina cuando no queda ninguna reserva activa y al menos una se completo", () => {
    expect(serviciosTerminados([])).toBe(false);
    expect(serviciosTerminados([{ estado: "completada" }, { estado: "en_curso" }])).toBe(false);
    expect(serviciosTerminados([{ estado: "cancelada" }])).toBe(false);
    expect(serviciosTerminados([{ estado: "completada" }, { estado: "cancelada" }])).toBe(true);
  });

  test("correo y telefono se comparan normalizados", () => {
    expect(normalizarCorreo("  Martin@Correo.COM ")).toBe("martin@correo.com");
    expect(normalizarCorreo("no-es-correo")).toBeNull();
    expect(normalizarTelefono("+57 320 826 2940")).toBe("3208262940");
    expect(normalizarTelefono("123")).toBeNull();
  });
});

describe("SaldoServicioService.registrarServicioTerminado", () => {
  test("crea el saldo con lo que dice la orden, no la solicitud, y avisa al cliente de la app", async () => {
    const { service, saldos, avisos } = servicio({
      pedidos: [{ id: 41, wooOrderId: "2434", usuario: { id: "u1", nombre: "Martin", correo: "m@x.co", telefono: 3001112233n } }],
    });
    tienda(ordenServicio());

    const res = await service.registrarServicioTerminado({ wooOrderId: "2434", orderKey: "wc_order_clave", montoSaldo: 1 });

    expect(res).toMatchObject({ creado: true, saldo: { montoSaldo: 35000, pagadoAntes: 36000, totalOrden: 71000 } });
    expect(saldos[0]).toMatchObject({
      pedidoAppId: 41,
      usuarioId: "u1",
      clienteCorreo: "martin@correo.com",
      clienteTelefono: "3208262940",
      servicios: "Revision de dano",
    });
    expect(avisos.notificarUsuario).toHaveBeenCalledWith(
      expect.objectContaining({ usuarioId: "u1", tipo: "saldo_servicio_pendiente", referenciaTipo: "SaldoServicio" }),
    );
    // Lo que se devuelve a WordPress no trae datos del cliente.
    expect(JSON.stringify(res)).not.toMatch(/martin@correo|3208262940/i);
  });

  test("clave de la orden incorrecta -> 403", async () => {
    const { service, saldos } = servicio();
    tienda(ordenServicio());
    await expect(service.registrarServicioTerminado({ wooOrderId: "2434", orderKey: "otra" })).rejects.toMatchObject({ status: 403 });
    expect(saldos).toHaveLength(0);
  });

  test("si quedan reservas activas, todavia no hay saldo", async () => {
    const { service, saldos } = servicio();
    tienda(ordenServicio(), [{ estado: "completada" }, { estado: "confirmada" }]);
    const res = await service.registrarServicioTerminado({ wooOrderId: "2434", orderKey: "wc_order_clave" });
    expect(res.saldo).toBeNull();
    expect(saldos).toHaveLength(0);
  });

  test("es idempotente: el segundo aviso devuelve el mismo saldo", async () => {
    const { service, saldos } = servicio();
    tienda(ordenServicio());
    await service.registrarServicioTerminado({ wooOrderId: "2434", orderKey: "wc_order_clave" });
    const otra = await service.registrarServicioTerminado({ wooOrderId: "2434", orderKey: "wc_order_clave" });
    expect(otra).toMatchObject({ creado: false, saldo: { id: 1 } });
    expect(saldos).toHaveLength(1);
  });
});

describe("bloqueo por mora", () => {
  function conSaldo(over: Fila = {}) {
    const ctx = servicio({ usuarios: [{ id: "u9", correo: "Ana@Correo.com", telefono: 3101234567n }] });
    ctx.saldos.push({
      id: 1,
      wooOrderId: "77",
      estado: EstadoSaldoServicio.PENDIENTE,
      usuarioId: null,
      clienteCorreo: "otra@correo.com",
      clienteTelefono: "0000000000",
      montoSaldo: new Prisma.Decimal(35000),
      ...over,
    });
    return ctx;
  }

  test("la app no deja pedir si el saldo es de su correo, aunque se pidio en la tienda", async () => {
    const { prisma } = conSaldo({ clienteCorreo: "ana@correo.com" });
    await expect(asegurarSinMora(prisma, "u9")).rejects.toMatchObject({ status: 409, message: expect.stringMatching(/\$35\.000/) });
  });

  test("ni si coincide solo el telefono", async () => {
    const { prisma } = conSaldo({ clienteTelefono: "3101234567" });
    await expect(asegurarSinMora(prisma, "u9")).rejects.toMatchObject({ status: 409 });
  });

  test("sin coincidencias, o con el saldo ya pagado, deja pedir", async () => {
    await expect(asegurarSinMora(conSaldo().prisma, "u9")).resolves.toBeUndefined();
    const pagado = conSaldo({ clienteCorreo: "ana@correo.com", estado: EstadoSaldoServicio.PAGADO });
    await expect(asegurarSinMora(pagado.prisma, "u9")).resolves.toBeUndefined();
  });

  test("la tienda pregunta por correo/telefono y solo recibe montos y ordenes", async () => {
    const { service } = conSaldo({ clienteCorreo: "ana@correo.com" });
    const res = await service.consultarMoraTienda({ correo: " ANA@correo.com", telefono: "" });
    expect(res).toEqual({ enMora: true, total: 35000, saldos: [{ wooOrderId: "77", montoSaldo: 35000 }] });
  });

  test("un pedido hecho sin poder verificar queda como incidencia y avisa al equipo", async () => {
    const { service, incidencias, avisos } = conSaldo({ clienteTelefono: "3101234567" });
    await service.consultarMoraTienda({ telefono: "310 123 4567", wooOrderId: "2500" });
    expect(incidencias).toEqual([{ saldoServicioId: 1, wooOrderId: "2500" }]);
    expect(avisos.alertarEquipo).toHaveBeenCalled();
  });
});

describe("pagar el saldo", () => {
  function conSaldoDe(usuarioId: string | null, correo: string | null, estado: EstadoSaldoServicio = EstadoSaldoServicio.PENDIENTE) {
    const ctx = servicio({
      usuarios: [
        { id: "u1", correo: "dueno@correo.com" },
        { id: "u2", correo: "otro@correo.com" },
      ],
    });
    ctx.saldos.push({
      id: 5,
      wooOrderId: "2434",
      estado,
      usuarioId,
      clienteCorreo: correo,
      montoSaldo: new Prisma.Decimal(35000),
      totalOrden: new Prisma.Decimal(71000),
      pagadoAntes: new Prisma.Decimal(36000),
    });
    return ctx;
  }

  test("el cobro es por el saldo registrado, en su canal y con prefijo SA", async () => {
    const { service, pagos } = conSaldoDe("u1", null);
    await service.pagarMio("u1", 5);
    expect(pagos.crearCobro).toHaveBeenCalledWith(
      expect.objectContaining({ canal: CanalPago.SALDO_SERVICIO, montoEsperado: 35000, saldoServicioId: 5, referencePrefix: "SA" }),
    );
    expect(pagos.crearCobro.mock.calls[0][0]).not.toHaveProperty("pedidoAppId");
  });

  test("tambien lo paga el dueno del correo aunque el pedido se hizo en la tienda", async () => {
    const { service, pagos } = conSaldoDe(null, "dueno@correo.com");
    await service.pagarMio("u1", 5);
    expect(pagos.crearCobro).toHaveBeenCalled();
  });

  test("el saldo de otra persona responde como inexistente", async () => {
    const { service, pagos } = conSaldoDe("u1", "dueno@correo.com");
    await expect(service.pagarMio("u2", 5)).rejects.toMatchObject({ status: 404 });
    await expect(service.obtenerMio("u2", 5)).rejects.toMatchObject({ status: 404 });
    expect(pagos.crearCobro).not.toHaveBeenCalled();
  });

  test("un saldo ya pagado no genera otro codigo", async () => {
    const { service } = conSaldoDe("u1", null, EstadoSaldoServicio.PAGADO_POR_FUERA);
    await expect(service.pagarMio("u1", 5)).rejects.toMatchObject({ status: 409 });
  });
});

describe("confirmacion y pago por fuera", () => {
  function contexto(over: Fila = {}) {
    return {
      cobroId: 50,
      canal: CanalPago.SALDO_SERVICIO,
      pedidoAppId: null,
      wooOrderId: "2434",
      usuarioId: null,
      saldoServicioId: 5,
      montoEsperado: new Prisma.Decimal(35000),
      referenceCode: "SA-1",
      ...over,
    };
  }
  function conSaldo(estado: EstadoSaldoServicio = EstadoSaldoServicio.PENDIENTE) {
    const ctx = servicio();
    ctx.saldos.push({ id: 5, wooOrderId: "2434", estado, montoSaldo: new Prisma.Decimal(35000), usuarioId: "u1" });
    return ctx;
  }

  test("el pago confirmado cierra el saldo pendiente", async () => {
    const { service, saldos, prisma } = conSaldo();
    await service.confirmarEnDominio(prisma, contexto());
    expect(saldos[0]).toMatchObject({ estado: EstadoSaldoServicio.PAGADO, cobroPagoId: 50 });
  });

  test("si ya estaba pagado por fuera, el dinero que llega queda para revisar", async () => {
    const { service, prisma } = conSaldo(EstadoSaldoServicio.PAGADO_POR_FUERA);
    await expect(service.confirmarEnDominio(prisma, contexto())).rejects.toBeInstanceOf(PedidoNoConfirmableError);
  });

  test("un monto distinto al saldo no lo confirma", async () => {
    const { service, saldos, prisma } = conSaldo();
    await expect(
      service.confirmarEnDominio(prisma, contexto({ montoEsperado: new Prisma.Decimal(1000) })),
    ).rejects.toBeInstanceOf(PedidoNoConfirmableError);
    expect(saldos[0].estado).toBe(EstadoSaldoServicio.PENDIENTE);
  });

  test("pago por fuera: queda con quien y por que, y levanta el bloqueo", async () => {
    const { service, saldos, avisos } = conSaldo();
    woo.mockResolvedValue({} as any);
    const actor = { id: "g1", nombre: "Gerente Uno", rol: "gerente", empresaId: "e1", residente: null } as any;

    await service.resolverPorFuera(actor, 5, { motivo: "Pago en efectivo al operario" });

    expect(saldos[0]).toMatchObject({
      estado: EstadoSaldoServicio.PAGADO_POR_FUERA,
      resueltoPorId: "g1",
      resolucionMotivo: "Pago en efectivo al operario",
    });
    expect(avisos.notificarUsuario).toHaveBeenCalledWith(expect.objectContaining({ tipo: "saldo_servicio_pagado" }));
    await expect(service.resolverPorFuera(actor, 5, { motivo: "Otra vez lo mismo" })).rejects.toMatchObject({ status: 409 });
  });
});
