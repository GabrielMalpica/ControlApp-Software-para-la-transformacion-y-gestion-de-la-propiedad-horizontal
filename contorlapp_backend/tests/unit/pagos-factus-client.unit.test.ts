const cacheStore = new Map<string, unknown>();
const cacheGet = jest.fn(async (key: string) => (cacheStore.has(key) ? cacheStore.get(key) : null));
const cacheSet = jest.fn(async (key: string, value: unknown) => {
  cacheStore.set(key, value);
});
const cacheDelete = jest.fn(async (...keys: string[]) => {
  keys.forEach((key) => cacheStore.delete(key));
});
// Sin Redis en estas pruebas: FactusPayClient cae al mutex local para el
// login (ver loginConLock en FactusPayClient.ts).
const getRedis = jest.fn(() => null);

jest.mock("../../src/services/RedisService", () => ({
  cacheGet: (...args: unknown[]) => (cacheGet as any)(...args),
  cacheSet: (...args: unknown[]) => (cacheSet as any)(...args),
  cacheDelete: (...args: unknown[]) => (cacheDelete as any)(...args),
  getRedis: (...args: unknown[]) => (getRedis as any)(...args),
}));

import {
  crearCobroFactus,
  consultarCobroFactus,
  isFactusPayConfigured,
  FACTUS_MONTO_MIN_COP,
  FACTUS_MONTO_MAX_COP,
} from "../../src/services/pagos/FactusPayClient";

describe("FactusPayClient", () => {
  const originalEnv = process.env;
  const originalFetch = global.fetch;

  beforeEach(() => {
    cacheStore.clear();
    cacheGet.mockClear();
    cacheSet.mockClear();
    cacheDelete.mockClear();
    getRedis.mockClear();
    process.env = {
      ...originalEnv,
      FACTUS_PAY_BASE_URL: "https://pay-api-sandbox.factus.test",
      FACTUS_PAY_EMAIL: "correo@test.com",
      FACTUS_PAY_PASSWORD: "secreto",
      FACTUS_PAY_ACCESS_KEY: "",
    };
  });

  afterEach(() => {
    process.env = originalEnv;
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  test("isFactusPayConfigured exige base url, correo y contrasena", () => {
    expect(isFactusPayConfigured()).toBe(true);
    process.env.FACTUS_PAY_PASSWORD = "";
    expect(isFactusPayConfigured()).toBe(false);
  });

  test("limites documentados de Factus (10.000 - 12.000.000 COP)", () => {
    expect(FACTUS_MONTO_MIN_COP).toBe(10_000);
    expect(FACTUS_MONTO_MAX_COP).toBe(12_000_000);
  });

  test("se autentica antes de la primera llamada y reusa el token en la siguiente", async () => {
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok-1" }) })
      .mockResolvedValueOnce({
        ok: true,
        status: 201,
        json: async () => ({ data: { reference_code: "CA-1", amount: 50000, status: "started", qr: null }, status: "success" }),
      })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ data: { reference_code: "CA-1", amount: 50000, status: "ready", qr: "x" }, status: "success" }),
      });
    global.fetch = fetchMock as unknown as typeof fetch;

    const creado = await crearCobroFactus("CA-1", 50000);
    expect(creado.status).toBe("started");
    const consultado = await consultarCobroFactus("CA-1");
    expect(consultado?.status).toBe("ready");

    expect(fetchMock).toHaveBeenCalledTimes(3); // auth + crear + consultar
    expect(fetchMock.mock.calls[0][0]).toBe("https://pay-api-sandbox.factus.test/auth");
    const authBody = JSON.parse((fetchMock.mock.calls[0][1] as RequestInit).body as string);
    expect(authBody).toEqual({ email: "correo@test.com", password: "secreto" });

    // La segunda llamada de negocio no vuelve a autenticarse: reusa el token.
    const headersConsulta = new Headers((fetchMock.mock.calls[2][1] as RequestInit).headers);
    expect(headersConsulta.get("Authorization")).toBe("Bearer tok-1");
  });

  test("reintenta con un login nuevo si el token quedo revocado (401)", async () => {
    cacheStore.set("factus:pay:token", "tok-viejo");
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: false, status: 401, json: async () => ({ message: "Credenciales inválidas" }) })
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok-nuevo" }) })
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        json: async () => ({ data: { reference_code: "CA-2", amount: 20000, status: "paid", qr: null }, status: "success" }),
      });
    global.fetch = fetchMock as unknown as typeof fetch;

    const resultado = await consultarCobroFactus("CA-2");
    expect(resultado?.status).toBe("paid");
    const ultimaLlamada = fetchMock.mock.calls[fetchMock.mock.calls.length - 1];
    const headers = new Headers((ultimaLlamada[1] as RequestInit).headers);
    expect(headers.get("Authorization")).toBe("Bearer tok-nuevo");
  });

  test("consultarCobroFactus devuelve null en 404 sin lanzar", async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok" }) })
      .mockResolvedValueOnce({ ok: false, status: 404, json: async () => ({ message: "Recaudo no encontrado" }) }) as unknown as typeof fetch;

    const resultado = await consultarCobroFactus("CA-inexistente");
    expect(resultado).toBeNull();
  });

  test("mapea un 429 a un error con status 429", async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok" }) })
      .mockResolvedValueOnce({ ok: false, status: 429, json: async () => ({ message: "Too many requests" }) }) as unknown as typeof fetch;

    await expect(crearCobroFactus("CA-3", 30000)).rejects.toMatchObject({ status: 429, upstreamStatus: 429 });
  });

  test("envia X-Factus-Access-Key solo si esta configurada", async () => {
    process.env.FACTUS_PAY_ACCESS_KEY = "clave-postman";
    const fetchMock = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok" }) })
      .mockResolvedValueOnce({
        ok: true,
        status: 201,
        json: async () => ({ data: { reference_code: "CA-4", amount: 20000, status: "started", qr: null }, status: "success" }),
      });
    global.fetch = fetchMock as unknown as typeof fetch;

    await crearCobroFactus("CA-4", 20000);
    const headersAuth = new Headers((fetchMock.mock.calls[0][1] as RequestInit).headers);
    expect(headersAuth.get("X-Factus-Access-Key")).toBe("clave-postman");
  });

  test("un cuerpo con forma inesperada se rechaza en vez de devolver datos a medias", async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ token: "tok" }) })
      .mockResolvedValueOnce({ ok: true, status: 200, json: async () => ({ data: { status: "ready" } }) }) as unknown as typeof fetch;

    await expect(crearCobroFactus("CA-5", 20000)).rejects.toMatchObject({ status: 502 });
  });
});
