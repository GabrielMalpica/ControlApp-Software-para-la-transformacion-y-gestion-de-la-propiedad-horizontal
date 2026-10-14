import { FactusPayError } from "../../src/services/pagos/errors";
import {
  detenerConciliacionPeriodica,
  iniciarConciliacionPeriodica,
} from "../../src/services/pagos/PagoReconciler";

const MIN = 60_000;
const HORA = 60 * MIN;

describe("iniciarConciliacionPeriodica", () => {
  let errorSpy: jest.SpyInstance;

  beforeEach(() => {
    jest.useFakeTimers();
    errorSpy = jest.spyOn(console, "error").mockImplementation(() => undefined);
    jest.spyOn(console, "info").mockImplementation(() => undefined);
  });

  afterEach(() => {
    detenerConciliacionPeriodica();
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  test("sin Factus configurado no programa nada", async () => {
    const ejecutar = jest.fn();
    iniciarConciliacionPeriodica({ ejecutar, ultima: async () => null, disponible: () => false });
    await jest.advanceTimersByTimeAsync(24 * HORA);
    expect(ejecutar).not.toHaveBeenCalled();
  });

  test("tras un fallo espera 6 h para reintentar y el log dice por que fallo", async () => {
    const ejecutar = jest.fn().mockRejectedValue(new FactusPayError("Credenciales invalidas", 401, 401));
    iniciarConciliacionPeriodica({ ejecutar, ultima: async () => null, disponible: () => true });

    await jest.advanceTimersByTimeAsync(2 * MIN);
    expect(ejecutar).toHaveBeenCalledTimes(1);
    expect(errorSpy).toHaveBeenCalledWith(
      "[pagos] fallo la conciliacion periodica",
      expect.objectContaining({ message: "Credenciales invalidas", upstreamStatus: 401, fallosSeguidos: 1 }),
    );

    // Antes se reintentaba cada 30 min: 48 errores iguales al dia.
    await jest.advanceTimersByTimeAsync(5 * HORA);
    expect(ejecutar).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(HORA + 30 * MIN);
    expect(ejecutar).toHaveBeenCalledTimes(2);
  });

  test("si ya corrio dentro del periodo no la repite", async () => {
    const ejecutar = jest.fn().mockResolvedValue(undefined);
    iniciarConciliacionPeriodica({ ejecutar, ultima: async () => new Date(), disponible: () => true });
    await jest.advanceTimersByTimeAsync(3 * HORA);
    expect(ejecutar).not.toHaveBeenCalled();
  });
});
