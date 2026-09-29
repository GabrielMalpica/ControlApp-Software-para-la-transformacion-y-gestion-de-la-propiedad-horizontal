import { CanalPago, EstadoCobro, Prisma } from "@prisma/client";
import { crearFakePagosPrisma } from "../helpers/fakePagosPrisma";

const crearCobroFactus = jest.fn();
const consultarCobroFactus = jest.fn();
let factusConfigurado = true;

jest.mock("../../src/services/pagos/FactusPayClient", () => ({
  crearCobroFactus: (...args: unknown[]) => crearCobroFactus(...args),
  consultarCobroFactus: (...args: unknown[]) => consultarCobroFactus(...args),
  isFactusPayConfigured: () => factusConfigurado,
  FACTUS_MONTO_MIN_COP: 10_000,
  FACTUS_MONTO_MAX_COP: 12_000_000,
}));

import { PagoService } from "../../src/services/pagos/PagoService";
import { FactusPayError, PedidoNoConfirmableError } from "../../src/services/pagos/errors";

function coleccion(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    reference_code: "CA-test",
    amount: 50_000,
    status: "started",
    created_at: new Date().toISOString(),
    qr: null,
    ...overrides,
  };
}

describe("PagoService", () => {
  beforeEach(() => {
    factusConfigurado = true;
    crearCobroFactus.mockReset();
    consultarCobroFactus.mockReset();
  });

  test("crearCobro rechaza si Factus no esta configurado", async () => {
    factusConfigurado = false;
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);

    await expect(service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 1 })).rejects.toThrow(
      FactusPayError,
    );
    expect(crearCobroFactus).not.toHaveBeenCalled();
  });

  test.each([9_999, 12_000_001])("crearCobro rechaza un monto fuera de los limites de Factus (%d)", async (monto) => {
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);

    await expect(service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: monto, pedidoAppId: 1 })).rejects.toMatchObject({
      status: 422,
    });
    expect(crearCobroFactus).not.toHaveBeenCalled();
  });

  test("crearCobro exige un pedido o una orden asociada", async () => {
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);

    await expect(service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000 })).rejects.toThrow();
  });

  test("crearCobro crea el cobro en Factus y agenda una reconsulta rapida si el QR no esta listo", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "started", qr: null }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);

    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    expect(crearCobroFactus).toHaveBeenCalledTimes(1);
    expect(cobro.estado).toBe(EstadoCobro.PENDIENTE);
    expect(cobro.estadoProveedor).toBe("started");
    expect(cobro.qrBase64).toBeNull();
    expect(cobro.proximaVerificacion?.getTime()).toBeLessThanOrEqual(Date.now() + 2_100);
  });

  test("crearCobro reutiliza un cobro vigente para el mismo pedido y monto sin llamar a Factus otra vez", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "data:image/png;base64,AAA" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);

    const primero = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    crearCobroFactus.mockClear();
    const segundo = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    expect(segundo.id).toBe(primero.id);
    expect(crearCobroFactus).not.toHaveBeenCalled();
  });

  test("verificarCobro marca FALLIDO cuando Factus rechaza el pago", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "started", qr: null }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "rejected" }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.FALLIDO);
    expect(actualizado.proximaVerificacion).toBeNull();
  });

  test("verificarCobro llama la pos-fallo del canal cuando Factus rechaza el pago", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "started", qr: null }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    const posFallo = jest.fn().mockResolvedValue(undefined);
    service.registrarPosFallo(CanalPago.CONTROLAPP, posFallo);

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "rejected" }));
    await service.verificarCobro(cobro.id);

    expect(posFallo).toHaveBeenCalledTimes(1);
    expect(posFallo.mock.calls[0][0]).toMatchObject({ id: cobro.id, estado: EstadoCobro.FALLIDO });
  });

  test("un fallo en la pos-fallo no revienta ni deja el cobro para reintentar (no hay dinero de por medio)", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "started", qr: null }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    service.registrarPosFallo(CanalPago.CONTROLAPP, async () => {
      throw new Error("Woo no responde");
    });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "rejected" }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.FALLIDO);
    expect(actualizado.pendienteSincronizarWoo).toBe(false);
  });

  test("verificarCobro confirma el pago y llama al confirmador del canal dentro de la misma transaccion", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "data:image/png;base64,AAA" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    const confirmador = jest.fn().mockResolvedValue(undefined);
    service.registrarConfirmador(CanalPago.CONTROLAPP, confirmador);

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.PAGADO);
    expect(actualizado.pagadoDetectadoEn).not.toBeNull();
    expect(confirmador).toHaveBeenCalledTimes(1);
    expect(confirmador.mock.calls[0][1]).toMatchObject({ cobroId: cobro.id, pedidoAppId: 7, referenceCode: cobro.referenceCode });
  });

  test("verificarCobro llama la pos-confirmacion (avisos de red) solo despues de que el pago quedo confirmado", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    const posConfirmacion = jest.fn().mockResolvedValue(undefined);
    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, posConfirmacion);
    service.registrarConfirmador(CanalPago.CONTROLAPP, jest.fn().mockResolvedValue(undefined));

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.PAGADO);
    expect(posConfirmacion).toHaveBeenCalledTimes(1);
    expect(posConfirmacion.mock.calls[0][0]).toMatchObject({ id: cobro.id, estado: EstadoCobro.PAGADO });
  });

  test("un fallo en la pos-confirmacion no revierte el pago ni lo hace fallar", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, async () => {
      throw new Error("no se pudo avisar a Woo");
    });
    service.registrarConfirmador(CanalPago.CONTROLAPP, jest.fn().mockResolvedValue(undefined));

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.PAGADO);
  });

  test("la pos-confirmacion NO se llama si el pago termino duplicado o huerfano", async () => {
    crearCobroFactus.mockImplementation(async (referenceCode: string) => coleccion({ reference_code: referenceCode, status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const posConfirmacion = jest.fn().mockResolvedValue(undefined);
    service.registrarPosConfirmacion(CanalPago.CONTROLAPP, posConfirmacion);
    service.registrarConfirmador(CanalPago.CONTROLAPP, jest.fn().mockResolvedValue(undefined));

    const uno = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    await prisma.pagoCobro.update({
      where: { id: uno.id },
      data: { estado: EstadoCobro.VENCIDO, expiraLocalEn: new Date(Date.now() - 1_000) },
    });
    const dos = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    consultarCobroFactus.mockImplementation(async (referenceCode: string) =>
      coleccion({ reference_code: referenceCode, status: "paid", amount: 50_000 }),
    );
    await service.verificarCobro(uno.id);
    posConfirmacion.mockClear();
    const duplicado = await service.verificarCobro(dos.id);

    expect(duplicado.estado).toBe(EstadoCobro.PAGADO_DUPLICADO);
    expect(posConfirmacion).not.toHaveBeenCalled();
  });

  test("verificarCobro marca DISCREPANCIA si el monto de Factus no coincide y avisa", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    const alertador = jest.fn().mockResolvedValue(undefined);
    service.registrarAlertador(alertador);
    const confirmador = jest.fn().mockResolvedValue(undefined);
    service.registrarConfirmador(CanalPago.CONTROLAPP, confirmador);

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 49_000 }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.DISCREPANCIA);
    expect(confirmador).not.toHaveBeenCalled();
    expect(alertador).toHaveBeenCalledTimes(1);
  });

  test("verificarCobro marca PAGADO_HUERFANO si el confirmador dice que el pedido ya no se puede confirmar", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    const alertador = jest.fn().mockResolvedValue(undefined);
    service.registrarAlertador(alertador);
    service.registrarConfirmador(CanalPago.CONTROLAPP, async () => {
      throw new PedidoNoConfirmableError("el pedido esta CANCELADO");
    });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    const actualizado = await service.verificarCobro(cobro.id);

    expect(actualizado.estado).toBe(EstadoCobro.PAGADO_HUERFANO);
    expect(alertador).toHaveBeenCalledTimes(1);
    expect(alertador.mock.calls[0][1]).toContain("el pedido esta CANCELADO");
  });

  test("verificarCobro no confirma dos veces el mismo pedido: el segundo cobro pagado queda PAGADO_DUPLICADO", async () => {
    crearCobroFactus.mockImplementation(async (referenceCode: string) => coleccion({ reference_code: referenceCode, status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const confirmador = jest.fn().mockResolvedValue(undefined);
    service.registrarConfirmador(CanalPago.CONTROLAPP, confirmador);
    const alertador = jest.fn().mockResolvedValue(undefined);
    service.registrarAlertador(alertador);

    // Dos cobros distintos para el mismo pedido (por ejemplo, uno vencio y
    // se genero otro, pero el primero termina pagandose igual).
    const uno = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    // Vencido localmente (para que crearCobro no lo reutilice) pero Factus
    // igual lo confirma despues: por eso VENCIDO sigue siendo un estado activo.
    await prisma.pagoCobro.update({
      where: { id: uno.id },
      data: { estado: EstadoCobro.VENCIDO, expiraLocalEn: new Date(Date.now() - 1_000) },
    });
    const dos = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    consultarCobroFactus.mockImplementation(async (referenceCode: string) =>
      coleccion({ reference_code: referenceCode, status: "paid", amount: 50_000 }),
    );

    const primeroConfirmado = await service.verificarCobro(uno.id);
    expect(primeroConfirmado.estado).toBe(EstadoCobro.PAGADO);
    expect(confirmador).toHaveBeenCalledTimes(1);

    const segundoConfirmado = await service.verificarCobro(dos.id);
    expect(segundoConfirmado.estado).toBe(EstadoCobro.PAGADO_DUPLICADO);
    // El confirmador de dominio (mueve el pedido a PAGADO) solo se llama una vez.
    expect(confirmador).toHaveBeenCalledTimes(1);
    expect(alertador).toHaveBeenCalledTimes(1);
  });

  test("si el confirmador falla por un error real, el cobro no queda pagado y puede reintentarse", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    let intentos = 0;
    service.registrarConfirmador(CanalPago.CONTROLAPP, async () => {
      intentos++;
      if (intentos === 1) throw new Error("la base de datos no responde");
    });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    await expect(service.verificarCobro(cobro.id)).rejects.toThrow("la base de datos no responde");

    const trasFallo = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(trasFallo.estado).not.toBe(EstadoCobro.PAGADO);
    expect(trasFallo.pagadoDetectadoEn).toBeNull();

    // El siguiente intento (worker o "Ya pague") si puede confirmar.
    const reintentado = await service.verificarCobro(cobro.id);
    expect(reintentado.estado).toBe(EstadoCobro.PAGADO);
    expect(intentos).toBe(2);
  });

  test("procesarPendientes reclama y verifica solo los cobros vencidos para reconsulta", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });
    // Simula que ya paso el tiempo del backoff.
    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { proximaVerificacion: new Date(Date.now() - 1_000) } });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    const resultado = await service.procesarPendientes(10);

    expect(resultado).toEqual({ procesados: 1, errores: 0 });
    const final = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(final.estado).toBe(EstadoCobro.PAGADO);
  });

  test("procesarPendientes no toca un cobro cuya reconsulta todavia no toca", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    await service.crearCobro({ canal: CanalPago.CONTROLAPP, montoEsperado: 50_000, pedidoAppId: 7 });

    const resultado = await service.procesarPendientes(10);
    expect(resultado).toEqual({ procesados: 0, errores: 0 });
  });

  test("un fallo en la pos-confirmacion marca el cobro para reintento y el worker lo reintenta pasado el minuto", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const cobro = await service.crearCobro({ canal: CanalPago.WOOCOMMERCE, montoEsperado: 50_000, wooOrderId: "900" });
    let intentos = 0;
    service.registrarPosConfirmacion(CanalPago.WOOCOMMERCE, async () => {
      intentos++;
      if (intentos === 1) throw new Error("Woo caido");
    });

    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    await service.verificarCobro(cobro.id);
    let actual = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(actual.estado).toBe(EstadoCobro.PAGADO);
    expect(actual.pendienteSincronizarWoo).toBe(true);

    // Todavia no pasaron 60 s desde el fallo: no reintenta.
    await service.reintentarPosConfirmaciones();
    expect(intentos).toBe(1);

    await prisma.pagoCobro.update({ where: { id: cobro.id }, data: { actualizadoEn: new Date(Date.now() - 120_000) } });
    await service.reintentarPosConfirmaciones();
    expect(intentos).toBe(2);
    actual = await prisma.pagoCobro.findUnique({ where: { id: cobro.id } });
    expect(actual.pendienteSincronizarWoo).toBe(false);
    expect(actual.estado).toBe(EstadoCobro.PAGADO);
  });

  test("marcarHuerfano deja el cobro pagado como huerfano y alerta una sola vez", async () => {
    crearCobroFactus.mockResolvedValue(coleccion({ status: "ready", qr: "x" }));
    const prisma = crearFakePagosPrisma();
    const service = new PagoService(prisma);
    const alertador = jest.fn().mockResolvedValue(undefined);
    service.registrarAlertador(alertador);
    const cobro = await service.crearCobro({ canal: CanalPago.WOOCOMMERCE, montoEsperado: 50_000, wooOrderId: "900" });
    consultarCobroFactus.mockResolvedValue(coleccion({ status: "paid", amount: 50_000 }));
    await service.verificarCobro(cobro.id);

    const huerfano = await service.marcarHuerfano(cobro.id, "orden cancelada");
    await service.marcarHuerfano(cobro.id, "orden cancelada");

    expect(huerfano.estado).toBe(EstadoCobro.PAGADO_HUERFANO);
    expect(alertador).toHaveBeenCalledTimes(1);
  });
});
