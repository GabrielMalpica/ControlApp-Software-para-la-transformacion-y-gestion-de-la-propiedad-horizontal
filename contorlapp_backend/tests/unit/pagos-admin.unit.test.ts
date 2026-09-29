import { CanalPago, EstadoCobro, Prisma, Rol } from "@prisma/client";
import { PagoAdminService } from "../../src/services/pagos/PagoAdminService";

const actor = { id: "ger-1", nombre: "Gerente", rol: Rol.gerente, empresaId: "EMP-1", residente: null } as any;

function cobro(overrides: Record<string, unknown> = {}) {
  return {
    id: 5,
    referenceCode: "CA-x",
    canal: CanalPago.CONTROLAPP,
    estado: EstadoCobro.PAGADO_HUERFANO,
    estadoProveedor: "paid",
    montoEsperado: new Prisma.Decimal(50000),
    montoProveedor: new Prisma.Decimal(50000),
    moneda: "COP",
    pedidoAppId: 41,
    wooOrderId: null,
    pagadoDetectadoEn: new Date("2026-09-25T10:00:00Z"),
    pendienteSincronizarWoo: false,
    creadoEn: new Date(),
    actualizadoEn: new Date(),
    pedidoApp: { id: 41, conjunto: { nombre: "Conjunto Uno" } },
    eventos: [],
    ...overrides,
  } as any;
}

function servicio() {
  const tx: any = {
    pagoCobro: { updateMany: jest.fn().mockResolvedValue({ count: 1 }) },
    pagoEvento: { create: jest.fn().mockResolvedValue({}) },
  };
  const prisma: any = {
    pagoCobro: {
      count: jest.fn().mockResolvedValue(1),
      findMany: jest.fn().mockResolvedValue([cobro()]),
      findFirst: jest.fn().mockResolvedValue(cobro()),
    },
    $transaction: jest.fn(async (fn: any) => fn(tx)),
  };
  return { service: new PagoAdminService(prisma), prisma, tx };
}

describe("PagoAdminService", () => {
  test("exige que el usuario tenga empresa", async () => {
    const { service } = servicio();
    await expect(service.listar({ ...actor, empresaId: null }, {})).rejects.toMatchObject({ status: 403 });
  });

  test("listar acota a la empresa (o a la tienda web sin pedido) y serializa sin campos internos", async () => {
    const { service, prisma } = servicio();
    const res = await service.listar(actor, { estado: "PAGADO_HUERFANO", pagina: "2", porPagina: "10" });

    const where = prisma.pagoCobro.findMany.mock.calls[0][0].where.AND;
    expect(JSON.stringify(where[0])).toContain("EMP-1");
    expect(where).toContainEqual({ estado: "PAGADO_HUERFANO" });
    expect(prisma.pagoCobro.findMany.mock.calls[0][0]).toMatchObject({ skip: 10, take: 10 });
    expect(res.items[0]).toMatchObject({ id: 5, requiereAccion: true, conjuntoNombre: "Conjunto Uno", montoEsperado: 50000 });
    expect(Object.keys(res.items[0])).not.toContain("qrBase64");
    expect(Object.keys(res.items[0])).not.toContain("lockedUntil");
  });

  test("requierenAccion=true filtra los estados que necesitan una decision", async () => {
    const { service, prisma } = servicio();
    await service.listar(actor, { requierenAccion: "true" });
    const filtros = prisma.pagoCobro.findMany.mock.calls[0][0].where.AND;
    expect(filtros.some((f: any) => f.estado?.in?.includes("PAGADO_HUERFANO"))).toBe(true);
  });

  test("busqueda por numero se interpreta como pedido y como orden de la tienda", async () => {
    const { service, prisma } = servicio();
    await service.listar(actor, { q: "41" });
    const or = prisma.pagoCobro.findMany.mock.calls[0][0].where.AND.find((f: any) => f.OR?.some((o: any) => o.wooOrderId)).OR;
    expect(or).toContainEqual({ pedidoAppId: 41 });
    expect(or).toContainEqual({ wooOrderId: "41" });
  });

  test("resolver cierra un cobro huerfano y deja constancia con quien lo hizo", async () => {
    const { service, tx } = servicio();
    await service.resolver(actor, 5, { accion: "DEVUELTO", motivo: "Se devolvio por Nequi" });

    expect(tx.pagoCobro.updateMany).toHaveBeenCalledWith({
      where: { id: 5, estado: EstadoCobro.PAGADO_HUERFANO },
      data: { estado: EstadoCobro.DEVUELTO },
    });
    expect(tx.pagoEvento.create).toHaveBeenCalledWith({
      data: expect.objectContaining({ tipo: "ACCION_MANUAL", actorId: "ger-1", estadoNuevo: EstadoCobro.DEVUELTO }),
    });
  });

  test("resolver rechaza cobros que no necesitan decision, sin motivo, o que cambiaron mientras tanto", async () => {
    const { service, prisma, tx } = servicio();
    prisma.pagoCobro.findFirst.mockResolvedValue(cobro({ estado: EstadoCobro.PAGADO }));
    await expect(service.resolver(actor, 5, { accion: "RESUELTO", motivo: "ya esta" })).rejects.toMatchObject({ status: 409 });

    prisma.pagoCobro.findFirst.mockResolvedValue(cobro());
    await expect(service.resolver(actor, 5, { accion: "RESUELTO", motivo: "no" })).rejects.toThrow();

    tx.pagoCobro.updateMany.mockResolvedValue({ count: 0 });
    await expect(service.resolver(actor, 5, { accion: "RESUELTO", motivo: "lo resolvi a mano" })).rejects.toMatchObject({ status: 409 });
  });

  test("resolver no encuentra cobros de otra empresa", async () => {
    const { service, prisma } = servicio();
    prisma.pagoCobro.findFirst.mockResolvedValue(null);
    await expect(service.resolver(actor, 5, { accion: "RESUELTO", motivo: "lo resolvi a mano" })).rejects.toMatchObject({ status: 404 });
  });

  test("reporte de recaudo suma solo lo confirmado, por dia o por canal", async () => {
    const { service, prisma } = servicio();
    prisma.pagoCobro.findMany.mockResolvedValue([
      { canal: "CONTROLAPP", montoEsperado: new Prisma.Decimal(50000), pagadoDetectadoEn: new Date("2026-09-24T15:00:00Z") },
      { canal: "WOOCOMMERCE", montoEsperado: new Prisma.Decimal(30000), pagadoDetectadoEn: new Date("2026-09-24T18:00:00Z") },
      { canal: "CONTROLAPP", montoEsperado: new Prisma.Decimal(20000), pagadoDetectadoEn: new Date("2026-09-25T09:00:00Z") },
    ]);
    const query = { desde: "2026-09-01", hasta: "2026-09-30" };

    const porDia = await service.reporteRecaudo(actor, query);
    expect(porDia.totalRecaudado).toBe(100000);
    expect(porDia.grupos).toEqual([
      { clave: "2026-09-24", total: 80000, cantidad: 2 },
      { clave: "2026-09-25", total: 20000, cantidad: 1 },
    ]);
    expect(prisma.pagoCobro.findMany.mock.calls[0][0].where.AND).toContainEqual({ estado: EstadoCobro.PAGADO });

    const porCanal = await service.reporteRecaudo(actor, { ...query, agrupar: "canal" });
    expect(porCanal.grupos).toEqual([
      { clave: "CONTROLAPP", total: 70000, cantidad: 2 },
      { clave: "WOOCOMMERCE", total: 30000, cantidad: 1 },
    ]);
  });
});
