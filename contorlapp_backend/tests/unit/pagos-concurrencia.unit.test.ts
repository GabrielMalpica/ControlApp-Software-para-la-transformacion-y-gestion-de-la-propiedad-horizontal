import { CanalPago, EstadoCobro, OrigenVerificacionPago } from "@prisma/client";
import { crearFakePagosPrisma } from "../helpers/fakePagosPrisma";

const crearCobroFactus = jest.fn();
const consultarCobroFactus = jest.fn();

jest.mock("../../src/services/pagos/FactusPayClient", () => ({
  crearCobroFactus: (...args: unknown[]) => crearCobroFactus(...args),
  consultarCobroFactus: (...args: unknown[]) => consultarCobroFactus(...args),
  isFactusPayConfigured: () => true,
  FACTUS_MONTO_MIN_COP: 10_000,
  FACTUS_MONTO_MAX_COP: 12_000_000,
}));

import { PagoService } from "../../src/services/pagos/PagoService";
import { FactusPayError } from "../../src/services/pagos/errors";

function coleccion(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    reference_code: "CA-test",
    amount: 50_000,
    status: "ready",
    created_at: new Date().toISOString(),
    qr: "x",
    ...overrides,
  };
}

function diferido<T>() {
  let resolver!: (valor: T) => void;
  let rechazar!: (error: unknown) => void;
  const promesa = new Promise<T>((ok, mal) => {
    resolver = ok;
    rechazar = mal;
  });
  return { promesa, resolver, rechazar };
}

async function cobroListo() {
  crearCobroFactus.mockResolvedValue(coleccion());
  const prisma = crearFakePagosPrisma();
  const service = new PagoService(prisma);
  const confirmador = jest.fn().mockResolvedValue(undefined);
  service.registrarConfirmador(CanalPago.CONTROLAPP, confirmador);
  const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
  return { prisma, service, cobro, confirmador };
}

const PAGADO_50K = () => coleccion({ status: "paid", amount: 50_000 });

describe("PagoService con varias vias consultando el mismo cobro (worker, Ya pague, webhook)", () => {
  beforeEach(() => {
    crearCobroFactus.mockReset();
    consultarCobroFactus.mockReset();
  });

  test("una respuesta vieja 'ready' que llega despues de confirmar no devuelve el cobro a pendiente", async () => {
    const { prisma, service, cobro } = await cobroListo();
    const lenta = diferido<ReturnType<typeof coleccion>>();
    consultarCobroFactus.mockReturnValueOnce(lenta.promesa).mockResolvedValueOnce(PAGADO_50K());

    const worker = service.verificarCobro(cobro.id, OrigenVerificacionPago.WORKER);
    const yaPague = await service.verificarCobro(cobro.id, OrigenVerificacionPago.USUARIO);
    expect(yaPague.estado).toBe(EstadoCobro.PAGADO);

    lenta.resolver(coleccion({ status: "ready" }));
    const delWorker = await worker;

    expect(delWorker.estado).toBe(EstadoCobro.PAGADO);
    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.estado).toBe(EstadoCobro.PAGADO);
  });

  test("un error de Factus que llega tarde no pisa un cobro ya confirmado", async () => {
    const { prisma, service, cobro } = await cobroListo();
    const lenta = diferido<ReturnType<typeof coleccion>>();
    consultarCobroFactus.mockReturnValueOnce(lenta.promesa).mockResolvedValueOnce(PAGADO_50K());

    const worker = service.verificarCobro(cobro.id, OrigenVerificacionPago.WORKER);
    await service.verificarCobro(cobro.id, OrigenVerificacionPago.USUARIO);
    lenta.rechazar(new FactusPayError("Factus no responde", 502));
    await worker;

    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.estado).toBe(EstadoCobro.PAGADO);
    expect(prisma._debug.eventos().filter((e: { tipo: string }) => e.tipo === "ERROR")).toHaveLength(0);
  });

  test("un rechazo viejo no pisa un PAGADO ni dispara el aviso de pago fallido", async () => {
    const { prisma, service, cobro } = await cobroListo();
    const posFallo = jest.fn().mockResolvedValue(undefined);
    service.registrarPosFallo(CanalPago.CONTROLAPP, posFallo);
    const lenta = diferido<ReturnType<typeof coleccion>>();
    consultarCobroFactus.mockReturnValueOnce(lenta.promesa).mockResolvedValueOnce(PAGADO_50K());

    const worker = service.verificarCobro(cobro.id, OrigenVerificacionPago.WORKER);
    await service.verificarCobro(cobro.id, OrigenVerificacionPago.USUARIO);
    lenta.resolver(coleccion({ status: "rejected" }));
    await worker;

    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.estado).toBe(EstadoCobro.PAGADO);
    expect(posFallo).not.toHaveBeenCalled();
  });

  test("diez verificaciones simultaneas confirman el pedido una sola vez", async () => {
    const { service, cobro, confirmador } = await cobroListo();
    const posConfirmacion = jest.fn().mockResolvedValue(undefined);
    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, posConfirmacion);
    consultarCobroFactus.mockResolvedValue(PAGADO_50K());

    const resultados = await Promise.all(
      Array.from({ length: 10 }, () => service.verificarCobro(cobro.id, OrigenVerificacionPago.WEBHOOK)),
    );

    expect(resultados.every((r) => r.estado === EstadoCobro.PAGADO)).toBe(true);
    expect(confirmador).toHaveBeenCalledTimes(1);
    expect(posConfirmacion).toHaveBeenCalledTimes(1);
  });

  test("la marca de avisos pendientes se pone en la misma transaccion que confirma y se apaga al terminar", async () => {
    crearCobroFactus.mockResolvedValue(coleccion());
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    let marcaDentroDeLaTransaccion: boolean | null = null;
    service.registrarConfirmador(CanalPago.CONTROLAPP, async (tx, contexto) => {
      const enTx = await tx.pagoCobro.findUnique({ where: { id: contexto.cobroId } });
      marcaDentroDeLaTransaccion = enTx?.pendienteSincronizarWoo ?? null;
    });
    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, jest.fn().mockResolvedValue(undefined));
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    consultarCobroFactus.mockResolvedValue(PAGADO_50K());
    const final = await service.verificarCobro(cobro.id);

    // Si el proceso muriera entre el commit y los avisos, la marca quedaria
    // puesta y el worker los reintentaria.
    expect(marcaDentroDeLaTransaccion).toBe(true);
    expect(final.pendienteSincronizarWoo).toBe(false);
  });

  test("tras una caida entre el commit y los avisos, el worker los corre", async () => {
    const { prisma, service, cobro } = await cobroListo();
    consultarCobroFactus.mockResolvedValue(PAGADO_50K());
    await service.verificarCobro(cobro.id);
    // Estado que deja una caida: pagado, marca puesta, avisos sin correr.
    await prisma.pagoCobro.update({
      where: { id: cobro.id },
      data: { pendienteSincronizarWoo: true, actualizadoEn: new Date(Date.now() - 120_000) },
    });
    const posConfirmacion = jest.fn().mockResolvedValue(undefined);
    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, posConfirmacion);

    await service.reintentarPosConfirmaciones();

    expect(posConfirmacion).toHaveBeenCalledTimes(1);
    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.pendienteSincronizarWoo).toBe(false);
  });

  test("guarda quien disparo la confirmacion, el vencimiento del QR, la llave Bre-B y el pagador recortado", async () => {
    const { service, cobro } = await cobroListo();
    consultarCobroFactus.mockResolvedValue(
      coleccion({
        status: "paid",
        amount: 50_000,
        qr_expires_at: "2026-10-15T15:20:00Z",
        breb_key: "@LLAVE",
        payer: { name: "Juan Perez", document_type: "CC", document_number: "1234567890" },
      }),
    );

    const final = await service.verificarCobro(cobro.id, OrigenVerificacionPago.WEBHOOK);

    expect(final).toMatchObject({
      estado: EstadoCobro.PAGADO,
      origenConfirmacion: OrigenVerificacionPago.WEBHOOK,
      ultimaVerificacionOrigen: OrigenVerificacionPago.WEBHOOK,
      brebKey: "@LLAVE",
      pagadorNombre: "Juan Perez",
      pagadorTipoDocumento: "CC",
      pagadorDocumentoUltimos4: "7890",
    });
    expect(final.qrExpiraEn?.toISOString()).toBe("2026-10-15T15:20:00.000Z");
    expect(JSON.stringify(final)).not.toContain("1234567890");
  });

  test("reabrirYVerificar: un cobro FALLIDO solo se reabre si la API dice paid", async () => {
    const { prisma, service, cobro } = await cobroListo();
    const posFallo = jest.fn().mockResolvedValue(undefined);
    service.registrarPosFallo(CanalPago.CONTROLAPP, posFallo);
    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { estado: EstadoCobro.FALLIDO } });

    consultarCobroFactus.mockResolvedValueOnce(coleccion({ status: "rejected" }));
    const sigue = await service.reabrirYVerificar(cobro.id, OrigenVerificacionPago.WEBHOOK);
    expect(sigue.estado).toBe(EstadoCobro.FALLIDO);
    expect(posFallo).not.toHaveBeenCalled();

    consultarCobroFactus.mockResolvedValueOnce(PAGADO_50K());
    const pagado = await service.reabrirYVerificar(cobro.id, OrigenVerificacionPago.WEBHOOK);
    expect(pagado.estado).toBe(EstadoCobro.PAGADO);
    expect(consultarCobroFactus).toHaveBeenCalledTimes(2);
  });

  test("reclamarParaVerificar: un solo reclamo a la vez y nunca sobre un cobro cerrado", async () => {
    const { prisma, service, cobro } = await cobroListo();

    expect(await service.reclamarParaVerificar(cobro.id)).toBe(true);
    expect(await service.reclamarParaVerificar(cobro.id)).toBe(false);

    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { estado: EstadoCobro.PAGADO, lockedUntil: null } });
    expect(await service.reclamarParaVerificar(cobro.id)).toBe(false);
  });
});
