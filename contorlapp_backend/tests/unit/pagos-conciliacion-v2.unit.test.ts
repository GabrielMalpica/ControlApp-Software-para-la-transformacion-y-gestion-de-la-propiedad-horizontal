import { EstadoCobro } from "@prisma/client";
import { PagoConciliacionService } from "../../src/services/pagos/PagoConciliacionService";

function remoto(reference_code: string, status = "paid") {
  return { reference_code, amount: 50000, status, qr: null };
}

/**
 * Prisma minimo: el listado de Factus no trae nada (asi solo actuan las
 * comprobaciones nuevas) y cada consulta findMany responde segun lo que pide.
 */
function armar(opts: { pagadosRecientes?: string[]; vencidos?: Array<{ id: number; referenceCode: string }> }) {
  const prisma: any = {
    pagoCobro: {
      findUnique: jest.fn().mockResolvedValue(null),
      findMany: jest.fn(async ({ where }: any) => {
        if (where.pendienteSincronizarWoo) return [];
        if (where.pagadoDetectadoEn) return (opts.pagadosRecientes ?? []).map((referenceCode) => ({ referenceCode }));
        if (where.OR) return opts.vencidos ?? [];
        return [];
      }),
    },
  };
  const pagos = {
    verificarCobro: jest.fn(async () => ({ estado: EstadoCobro.PAGADO })),
    reabrirYVerificar: jest.fn(),
    cerrarVencido: jest.fn().mockResolvedValue(true),
  };
  const consultar = jest.fn();
  const alertar = jest.fn().mockResolvedValue(undefined);
  const listar = jest.fn(async () => ({ items: [], page: 1, lastPage: 99 }));
  const service = new PagoConciliacionService(prisma, pagos as any, listar as any, alertar, 1, () => false, {
    consultar,
  });
  return { service, pagos, consultar, alertar };
}

describe("conciliacion: doble verificacion de pagados recientes", () => {
  test("un cobro pagado aqui que Factus no da por pagado es una anomalia grave (alerta, sin correccion)", async () => {
    const { service, consultar, alertar } = armar({ pagadosRecientes: ["CA-1", "CA-2"] });
    consultar.mockImplementation(async (ref: string) => (ref === "CA-1" ? remoto("CA-1") : remoto("CA-2", "ready")));

    const r = await service.ejecutar();

    expect(r.verificadosRecientes).toBe(2);
    expect(r.anomalias).toEqual([
      expect.objectContaining({ tipo: "PAGADO_LOCAL_NO_EN_FACTUS", referenceCode: "CA-2" }),
    ]);
    expect(alertar).toHaveBeenCalledTimes(1);
  });

  test("si Factus no responde no se concluye nada", async () => {
    const { service, consultar } = armar({ pagadosRecientes: ["CA-1"] });
    consultar.mockRejectedValue(new Error("timeout"));

    const r = await service.ejecutar();

    expect(r.verificadosRecientes).toBe(0);
    expect(r.anomalias).toEqual([]);
  });

  test("funciona aunque el listado de Factus no se haya recorrido completo", async () => {
    const { service, consultar } = armar({ pagadosRecientes: ["CA-1"] });
    consultar.mockResolvedValue(null);

    const r = await service.ejecutar();

    expect(r.completo).toBe(false);
    expect(r.anomalias[0]).toMatchObject({ tipo: "PAGADO_LOCAL_NO_EN_FACTUS", referenceCode: "CA-1" });
  });
});

describe("conciliacion: cobros con el QR vencido", () => {
  test("sin pago en Factus se cierran", async () => {
    const { service, consultar, pagos } = armar({ vencidos: [{ id: 3, referenceCode: "CA-3" }] });
    consultar.mockResolvedValue(remoto("CA-3", "ready"));

    const r = await service.ejecutar();

    expect(pagos.cerrarVencido).toHaveBeenCalledWith(3, expect.stringContaining("vencio"));
    expect(r.cerradosPorVencimiento).toBe(1);
    expect(r.anomalias).toEqual([]);
  });

  test("si Factus lo cobro igual, se confirma por el camino normal y queda como corregido", async () => {
    const { service, consultar, pagos } = armar({ vencidos: [{ id: 3, referenceCode: "CA-3" }] });
    consultar.mockResolvedValue(remoto("CA-3"));

    const r = await service.ejecutar();

    expect(pagos.verificarCobro).toHaveBeenCalledWith(3, "CONCILIACION");
    expect(pagos.cerrarVencido).not.toHaveBeenCalled();
    expect(r.anomalias[0]).toMatchObject({ tipo: "PAGADO_EN_FACTUS_NO_LOCAL", corregida: true });
  });

  test("si Factus no responde se deja para la siguiente corrida", async () => {
    const { service, consultar, pagos } = armar({ vencidos: [{ id: 3, referenceCode: "CA-3" }] });
    consultar.mockRejectedValue(new Error("timeout"));

    await service.ejecutar();

    expect(pagos.cerrarVencido).not.toHaveBeenCalled();
  });
});
