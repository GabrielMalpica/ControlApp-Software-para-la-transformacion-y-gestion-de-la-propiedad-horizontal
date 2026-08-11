export type WooApiNamespace = "store" | "rest" | "plugin";

export class WooFetchError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly upstreamStatus?: number,
  ) {
    super(message);
    this.name = "WooFetchError";
  }
}

function trimTrailingSlash(value: string) {
  return value.endsWith("/") ? value.slice(0, -1) : value;
}

export function getWooBaseUrl() {
  const raw =
    process.env.WOOCOMMERCE_BASE_URL?.trim() ||
    process.env.ECOMMERCE_BASE_URL?.trim() ||
    "";
  if (!raw) {
    throw new WooFetchError("El canal de compras no tiene una tienda configurada", 500);
  }

  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new WooFetchError("La direccion configurada para la tienda no es valida", 500);
  }

  if (url.protocol !== "https:" || url.username || url.password) {
    throw new WooFetchError("La direccion configurada para la tienda no es segura", 500);
  }

  url.hash = "";
  url.search = "";
  return trimTrailingSlash(url.toString());
}

function getWooCredentials() {
  return {
    key:
      process.env.WOOCOMMERCE_API_KEY?.trim() ||
      process.env.WOOCOMMERCE_CONSUMER_KEY?.trim() ||
      "",
    secret:
      process.env.WOOCOMMERCE_SECRET_KEY?.trim() ||
      process.env.WOOCOMMERCE_CONSUMER_SECRET?.trim() ||
      "",
  };
}

export function buildWooUrl(
  namespace: WooApiNamespace,
  path: string,
  query: Record<string, string | number | boolean | undefined> = {},
) {
  const prefix =
    namespace === "store"
      ? "/wp-json/wc/store/v1"
      : namespace === "rest"
        ? "/wp-json/wc/v3"
        : "/wp-json/cl/v1";
  const safePath = path.startsWith("/") ? path : `/${path}`;
  const url = new URL(`${getWooBaseUrl()}${prefix}${safePath}`);
  for (const [key, value] of Object.entries(query)) {
    if (value == null || value === "") continue;
    url.searchParams.set(key, String(value));
  }
  return url.toString();
}

export async function wooFetch<T>(
  url: string,
  init: RequestInit = {},
  options: {
    requireAuth?: boolean;
    timeoutMs?: number;
    failureMessage?: string;
    mapConflict?: boolean;
  } = {},
) {
  const base = new URL(getWooBaseUrl());
  const target = new URL(url);
  if (target.origin !== base.origin || !["http:", "https:"].includes(target.protocol)) {
    throw new WooFetchError("La solicitud a la tienda fue bloqueada por seguridad", 500);
  }

  const credentials = getWooCredentials();
  if (options.requireAuth && (!credentials.key || !credentials.secret)) {
    throw new WooFetchError(
      "El canal de compras no esta configurado para crear pedidos. Contacta al administrador",
      503,
    );
  }

  const headers = new Headers(init.headers);
  headers.set("Accept", "application/json");
  if (init.body != null && !headers.has("Content-Type")) {
    headers.set("Content-Type", "application/json");
  }
  // La Store API y los endpoints publicos de disponibilidad no requieren
  // credenciales. Enviar Authorization en esas rutas puede activar reglas del
  // CDN/WAF y, ademas, expone secretos a endpoints que no los necesitan.
  if (options.requireAuth && credentials.key && credentials.secret) {
    headers.set(
      "Authorization",
      `Basic ${Buffer.from(`${credentials.key}:${credentials.secret}`).toString("base64")}`,
    );
  }

  let response: Response;
  try {
    response = await fetch(target, {
      ...init,
      headers,
      signal: init.signal ?? AbortSignal.timeout(options.timeoutMs ?? 10_000),
    });
  } catch (error) {
    if (error instanceof Error && ["AbortError", "TimeoutError"].includes(error.name)) {
      throw new WooFetchError("La tienda tardo demasiado en responder. Intenta nuevamente", 504);
    }
    throw new WooFetchError("No fue posible conectar con la tienda. Intenta nuevamente", 502);
  }

  if (!response.ok) {
    let upstreamMessage = "";
    try {
      const payload = (await response.json()) as { message?: unknown };
      upstreamMessage = typeof payload.message === "string" ? payload.message.trim() : "";
    } catch {
      upstreamMessage = "";
    }
    const status = options.mapConflict && response.status === 409 ? 409 : 502;
    const message =
      status === 409
        ? upstreamMessage || "El turno seleccionado ya no tiene cupos disponibles"
        : options.failureMessage || "La tienda no pudo completar la solicitud. Intenta nuevamente";
    throw new WooFetchError(message, status, response.status);
  }

  try {
    return (await response.json()) as T;
  } catch {
    throw new WooFetchError(
      "La tienda respondio sin datos validos. Revisa la API REST de WordPress",
      502,
      response.status,
    );
  }
}
