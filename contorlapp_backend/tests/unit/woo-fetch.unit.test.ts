import {
  buildWooUrl,
  getWooBaseUrl,
  WooFetchError,
  wooFetch,
} from "../../src/services/wooFetch";

describe("wooFetch", () => {
  const originalEnv = process.env;
  const originalFetch = global.fetch;

  beforeEach(() => {
    process.env = {
      ...originalEnv,
      WOOCOMMERCE_BASE_URL: "https://store.example.test",
      WOOCOMMERCE_API_KEY: "ck_test",
      WOOCOMMERCE_SECRET_KEY: "cs_test",
    };
  });

  afterEach(() => {
    process.env = originalEnv;
    global.fetch = originalFetch;
    jest.restoreAllMocks();
  });

  test("rechaza HTTP incluso fuera de produccion", () => {
    process.env.WOOCOMMERCE_BASE_URL = "http://store.example.test";

    expect(() => getWooBaseUrl()).toThrow("La direccion configurada para la tienda no es segura");
  });

  test("no envia credenciales a la Store API publica", async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: jest.fn().mockResolvedValue({ id: 1978 }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    await wooFetch(buildWooUrl("store", "/products/1978"));

    const headers = new Headers(fetchMock.mock.calls[0][1].headers);
    expect(headers.has("Authorization")).toBe(false);
  });

  test("envia Basic auth solamente a endpoints protegidos", async () => {
    const fetchMock = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: jest.fn().mockResolvedValue({ id: 1001 }),
    });
    global.fetch = fetchMock as unknown as typeof fetch;

    await wooFetch(
      buildWooUrl("rest", "/orders"),
      { method: "POST", body: "{}" },
      { requireAuth: true },
    );

    const headers = new Headers(fetchMock.mock.calls[0][1].headers);
    expect(headers.get("Authorization")).toBe(
      `Basic ${Buffer.from("ck_test:cs_test").toString("base64")}`,
    );
  });

  test("convierte una respuesta JSON vacia en un error 502 entendible", async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 200,
      json: jest.fn().mockRejectedValue(new SyntaxError("Unexpected end of JSON input")),
    }) as unknown as typeof fetch;

    await expect(wooFetch(buildWooUrl("store", "/products/1978"))).rejects.toMatchObject<
      Partial<WooFetchError>
    >({
      name: "WooFetchError",
      status: 502,
      upstreamStatus: 200,
      message: "La tienda respondio sin datos validos. Revisa la API REST de WordPress",
    });
  });
});
