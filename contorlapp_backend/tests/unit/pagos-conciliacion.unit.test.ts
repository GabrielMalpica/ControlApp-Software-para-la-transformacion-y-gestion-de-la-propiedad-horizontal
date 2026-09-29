import { EstadoCobro, Prisma } from "@prisma/client";
import { PagoConciliacionService } from "../../src/services/pagos/PagoConciliacionService";

function local(overrides: Record<string, unknown> = {}) {
  return {
    id: 1,
    referenceCode: "CA-1",
    estado: EstadoCobro.PAGADO,
    montoEsperado: new Prisma.Decimal(50000),
    ...overrides,
  } as any;
}

function remoto(reference_code: string, amount = 50000) {
  return { reference_code, amount, status: "paid", qr: null };
}

function armar(opts: {
  paginas: Array<Array<ReturnType<typeof remoto>>>;
  locales?: Record<string, any>;
  pagadosLocales?: any[];
  sinSincronizar?: any[];
}) {
  const prisma: any = {
    pagoCobro: {
      findUnique: jest.fn(async ({ where }: any) => opts.locales?.[where.referenceCode] ?? null),
      findMany: jest.fn(async ({ where }: any) => {
        if (where.pendienteSincronizarWoo) return opts.sinSincronizar ?? [];
        return opts.pagadosLocales ?? [];
      }),
    },
  };
  const pagos = {
    verificarCobro: jest.fn(async () => local({ estado: EstadoCobro.PAGADO })),
    reabrirYVerificar: jest.fn(async () => local({ estado: EstadoCobro.PAGADO })),
  };
  const listar = jest.fn(async ({ page }: { page?: number }) => {
    const idx = (page ?? 1) - 1;
    return { items: opts.paginas[idx] ?? [], page: idx + 1, lastPage: opts.paginas.length };
  });
  const alertar = jest.fn().mockResolvedValue(undefined);
  return { service: new PagoConciliacionService(prisma, pagos as any, listar as any, alertar, 10), pagos, listar, alertar };
}

describe("PagoConciliacionService", () => {
  test("todo consistente: sin anomalias y sin alertas", async () => {
    const { service, alertar } = armar({
      paginas: [[remoto("CA-1")]],
      locales: { "CA-1": local() },
      pagadosLocales: [local()],
    });
    const r = await service.ejecutar();
    expect(r.anomalias).toEqual([]);
    expect(r.completo).toBe(true);
    expect(r.remotosPagados).toBe(1);
    expect(alertar).not.toHaveBeenCalled();
  });

  test("recorre todas las paginas del listado", async () => {
    const { service, listar } = armar({ paginas: [[remoto("CA-1")], [remoto("CA-2")]], locales: { "CA-1": local(), "CA-2": local({ referenceCode: "CA-2" }) }, pagadosLocales: [local(), local({ referenceCode: "CA-2" })] });
    const r = await service.ejecutar();
    expect(listar).toHaveBeenCalledTimes(2);
    expect(r.remotosPagados).toBe(2);
  });

  test("pagado en Factus pero pendiente aqui: lo verifica y lo reporta como corregido", async () => {
    const { service, pagos, alertar } = armar({
      paginas: [[remoto("CA-1")]],
      locales: { "CA-1": local({ estado: EstadoCobro.PENDIENTE }) },
      pagadosLocales: [local()],
    });
    const r = await service.ejecutar();
    expect(pagos.verificarCobro).toHaveBeenCalled();
    expect(r.anomalias[0]).toMatchObject({ tipo: "PAGADO_EN_FACTUS_NO_LOCAL", corregida: true });
    expect(alertar).not.toHaveBeenCalled();
  });

  test("abandonado o fallido aqui: lo reabre", async () => {
    const { service, pagos } = armar({
      paginas: [[remoto("CA-1")]],
      locales: { "CA-1": local({ estado: EstadoCobro.ABANDONADO }) },
      pagadosLocales: [local()],
    });
    await service.ejecutar();
    expect(pagos.reabrirYVerificar).toHaveBeenCalledWith(1);
  });

  test("recaudo con nuestro prefijo que no existe aqui: alerta; con otro prefijo se ignora", async () => {
    const { service, alertar } = armar({ paginas: [[remoto("WC-zzz"), remoto("FACT-9")]] });
    const r = await service.ejecutar();
    expect(r.anomalias).toHaveLength(1);
    expect(r.anomalias[0]).toMatchObject({ tipo: "SIN_COBRO_LOCAL", referenceCode: "WC-zzz" });
    expect(alertar).toHaveBeenCalledTimes(1);
  });

  test("monto distinto entre Factus y lo cobrado", async () => {
    const { service } = armar({
      paginas: [[remoto("CA-1", 49000)]],
      locales: { "CA-1": local() },
      pagadosLocales: [local()],
    });
    const r = await service.ejecutar();
    expect(r.anomalias[0].tipo).toBe("MONTO_DISTINTO");
  });

  test("local pagado que Factus no lista: solo se comprueba si el listado se recorrio completo", async () => {
    const completo = armar({ paginas: [[]], pagadosLocales: [local()] });
    expect((await completo.service.ejecutar()).anomalias[0].tipo).toBe("PAGADO_LOCAL_NO_EN_FACTUS");

    // Con el tope de paginas alcanzado no se puede afirmar que falte.
    const prisma: any = { pagoCobro: { findUnique: jest.fn(), findMany: jest.fn().mockResolvedValue([local()]) } };
    const listar = jest.fn(async ({ page }: any) => ({ items: [], page, lastPage: 99 }));
    const service = new PagoConciliacionService(prisma, {} as any, listar as any, jest.fn(), 2);
    const r = await service.ejecutar();
    expect(r.completo).toBe(false);
    expect(r.anomalias.some((a) => a.tipo === "PAGADO_LOCAL_NO_EN_FACTUS")).toBe(false);
  });

  test("avisos de sincronizacion con la tienda que llevan mas de una hora", async () => {
    const { service, alertar } = armar({ paginas: [[]], sinSincronizar: [{ referenceCode: "WC-1" }] });
    const r = await service.ejecutar();
    expect(r.anomalias[0].tipo).toBe("SINCRONIZACION_PENDIENTE");
    expect(alertar).toHaveBeenCalled();
  });
});
