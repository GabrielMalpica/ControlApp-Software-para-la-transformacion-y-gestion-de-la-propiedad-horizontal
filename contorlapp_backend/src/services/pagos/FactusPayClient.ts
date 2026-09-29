import { z } from "zod";
import { cacheGet, cacheSet, cacheDelete, getRedis } from "../RedisService";
import { FactusPayError } from "./errors";

// Documentacion oficial: https://pay-developers.factus.com.co/ (Autenticacion,
// Recaudos crear/listar/ver). No hay webhooks documentados: la confirmacion
// del pago se hace consultando el recaudo (ver PagoService).
const TOKEN_CACHE_KEY = "factus:pay:token";
// Factus no documenta expiracion por tiempo ("un solo token activo por
// usuario"; cada login revoca el anterior). Se cachea por precaucion y se
// refresca de inmediato ante un 401.
const TOKEN_TTL_SECONDS = 60 * 60 * 12;
const LOGIN_LOCK_KEY = "factus:pay:login-lock";
const LOGIN_LOCK_TTL_MS = 15_000;
const LOGIN_LOCK_MAX_ESPERAS = 20;
const LOGIN_LOCK_ESPERA_MS = 500;

export const FACTUS_MONTO_MIN_COP = 10_000;
export const FACTUS_MONTO_MAX_COP = 12_000_000;

const CollectionDataSchema = z.object({
  reference_code: z.string(),
  amount: z.coerce.number(),
  status: z.string(),
  created_at: z.string().optional(),
  qr: z.string().nullable().optional(),
});

const CollectionResponseSchema = z.object({
  data: CollectionDataSchema,
  status: z.string().optional(),
  message: z.string().optional(),
});

const ListResponseSchema = z.object({
  data: z.array(CollectionDataSchema),
  meta: z
    .object({ current_page: z.coerce.number(), last_page: z.coerce.number(), total: z.coerce.number().optional() })
    .optional(),
});

export type FactusCollectionPage = { items: FactusCollection[]; page: number; lastPage: number };

const AuthResponseSchema = z.object({ token: z.string().min(1) });

export type FactusCollection = z.infer<typeof CollectionDataSchema>;

function getConfig() {
  return {
    baseUrl: (process.env.FACTUS_PAY_BASE_URL ?? "").trim().replace(/\/+$/, ""),
    email: (process.env.FACTUS_PAY_EMAIL ?? "").trim(),
    password: process.env.FACTUS_PAY_PASSWORD ?? "",
    accessKey: (process.env.FACTUS_PAY_ACCESS_KEY ?? "").trim(),
  };
}

export function isFactusPayConfigured(): boolean {
  const { baseUrl, email, password } = getConfig();
  return Boolean(baseUrl && email && password);
}

function mapUpstreamStatus(upstream: number): number {
  if (upstream === 401) return 401;
  if (upstream === 404) return 404;
  if (upstream === 422) return 422;
  if (upstream === 429) return 429;
  return 502;
}

async function requestJson<T>(
  url: string,
  init: RequestInit,
  schema: z.ZodType<T>,
  timeoutMs: number,
): Promise<T> {
  let response: Response;
  try {
    response = await fetch(url, { ...init, signal: AbortSignal.timeout(timeoutMs) });
  } catch (error) {
    if (error instanceof Error && ["AbortError", "TimeoutError"].includes(error.name)) {
      throw new FactusPayError("Factus Pay tardo demasiado en responder. Intenta nuevamente", 504);
    }
    throw new FactusPayError("No fue posible conectar con Factus Pay", 502);
  }

  let payload: unknown = null;
  try {
    payload = await response.json();
  } catch {
    payload = null;
  }

  if (!response.ok) {
    const message =
      payload && typeof payload === "object" && "message" in payload
        ? String((payload as { message?: unknown }).message ?? "")
        : "";
    throw new FactusPayError(
      message || `Factus Pay respondio con un error (${response.status})`,
      mapUpstreamStatus(response.status),
      response.status,
    );
  }

  const parsed = schema.safeParse(payload);
  if (!parsed.success) {
    throw new FactusPayError("Factus Pay respondio con un formato inesperado", 502);
  }
  return parsed.data;
}

async function login(): Promise<string> {
  const { baseUrl, email, password, accessKey } = getConfig();
  if (!baseUrl || !email || !password) {
    throw new FactusPayError("Factus Pay no esta configurado", 503);
  }
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    Accept: "application/json",
  };
  if (accessKey) headers["X-Factus-Access-Key"] = accessKey;

  const { token } = await requestJson(
    `${baseUrl}/auth`,
    { method: "POST", headers, body: JSON.stringify({ email, password }) },
    AuthResponseSchema,
    8_000,
  );
  await cacheSet(TOKEN_CACHE_KEY, token, TOKEN_TTL_SECONDS);
  return token;
}

let loginLocal: Promise<string> | null = null;

/**
 * Factus solo permite un token activo por usuario: cada login revoca el
 * anterior. Este lock (Redis SET NX, con un mutex local de respaldo si no
 * hay Redis) evita que dos instancias del backend se revoquen el token entre
 * si al refrescarlo a la vez.
 */
async function loginConLock(): Promise<string> {
  const redis = getRedis();
  if (!redis) {
    if (!loginLocal) {
      loginLocal = login().finally(() => {
        loginLocal = null;
      });
    }
    return loginLocal;
  }

  const valorPropio = `${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  for (let intento = 0; intento < LOGIN_LOCK_MAX_ESPERAS; intento++) {
    const adquirido = await redis
      .set(LOGIN_LOCK_KEY, valorPropio, "PX", LOGIN_LOCK_TTL_MS, "NX")
      .catch(() => null);
    if (adquirido === "OK") {
      try {
        // Alguien pudo haber refrescado el token mientras esperabamos turno.
        const cacheado = await cacheGet<string>(TOKEN_CACHE_KEY);
        if (cacheado) return cacheado;
        return await login();
      } finally {
        const actual = await redis.get(LOGIN_LOCK_KEY).catch(() => null);
        if (actual === valorPropio) await redis.del(LOGIN_LOCK_KEY).catch(() => undefined);
      }
    }
    await new Promise((resolve) => setTimeout(resolve, LOGIN_LOCK_ESPERA_MS));
    const cacheado = await cacheGet<string>(TOKEN_CACHE_KEY);
    if (cacheado) return cacheado;
  }
  // No se logro coordinar el lock a tiempo: se intenta de todas formas en
  // vez de fallar la operacion completa.
  return login();
}

async function authorizedFetch<T>(
  path: string,
  init: RequestInit,
  schema: z.ZodType<T>,
  timeoutMs: number,
): Promise<T> {
  const { baseUrl } = getConfig();
  if (!baseUrl) throw new FactusPayError("Factus Pay no esta configurado", 503);

  let token = await cacheGet<string>(TOKEN_CACHE_KEY);
  if (!token) token = await loginConLock();

  const intentar = (bearer: string) =>
    requestJson(
      `${baseUrl}${path}`,
      {
        ...init,
        headers: { ...(init.headers as Record<string, string> | undefined), Authorization: `Bearer ${bearer}`, Accept: "application/json" },
      },
      schema,
      timeoutMs,
    );

  try {
    return await intentar(token);
  } catch (error) {
    if (error instanceof FactusPayError && error.upstreamStatus === 401) {
      await cacheDelete(TOKEN_CACHE_KEY);
      const nuevo = await loginConLock();
      return intentar(nuevo);
    }
    throw error;
  }
}

/**
 * Crea (o recupera, si ya existe) un recaudo en Factus. El endpoint es
 * idempotente por reference_code: reintentarlo tras un timeout, o llamarlo de
 * nuevo para refrescar el QR/estado de un cobro que ya se creo, es seguro.
 */
export async function crearCobroFactus(referenceCode: string, amountCop: number): Promise<FactusCollection> {
  const resultado = await authorizedFetch(
    "/v1/collections",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ reference_code: referenceCode, amount: amountCop }),
    },
    CollectionResponseSchema,
    12_000,
  );
  return resultado.data;
}

/** null si Factus no tiene (todavia) un recaudo con esa referencia. */
export async function consultarCobroFactus(referenceCode: string): Promise<FactusCollection | null> {
  try {
    const resultado = await authorizedFetch(
      `/v1/collections/${encodeURIComponent(referenceCode)}`,
      { method: "GET" },
      CollectionResponseSchema,
      8_000,
    );
    return resultado.data;
  } catch (error) {
    if (error instanceof FactusPayError && error.upstreamStatus === 404) return null;
    throw error;
  }
}

/**
 * Una pagina (15 recaudos) del listado de Factus. Sirve para conciliar: el
 * listado NO trae el QR y no documenta filtro por fecha ni orden, por eso
 * la conciliacion recorre las paginas hasta un tope (ver PagoConciliacionService).
 */
export async function listarCobrosFactus(params: { status?: string; page?: number }): Promise<FactusCollectionPage> {
  const query = new URLSearchParams();
  if (params.status) query.set("status", params.status);
  if (params.page && params.page > 1) query.set("page", String(params.page));
  const qs = query.toString();
  const resultado = await authorizedFetch(
    `/v1/collections${qs ? `?${qs}` : ""}`,
    { method: "GET" },
    ListResponseSchema,
    12_000,
  );
  return {
    items: resultado.data,
    page: resultado.meta?.current_page ?? params.page ?? 1,
    lastPage: resultado.meta?.last_page ?? 1,
  };
}
