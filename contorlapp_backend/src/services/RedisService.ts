import Redis from "ioredis";

let redis: Redis | null | undefined;
let warned = false;
const inFlight = new Map<string, Promise<unknown>>();
const localCache = new Map<string, { value: unknown; expiresAt: number }>();
const MAX_LOCAL_CACHE_ENTRIES = 5_000;

function warnOnce(message: string) {
  if (warned) return;
  warned = true;
  console.warn(`[redis] ${message}`);
}

function setLocalCache(key: string, value: unknown, ttlSeconds: number) {
  const now = Date.now();
  if (localCache.size >= MAX_LOCAL_CACHE_ENTRIES) {
    for (const [candidate, entry] of localCache) {
      if (entry.expiresAt <= now) localCache.delete(candidate);
    }
  }
  while (localCache.size >= MAX_LOCAL_CACHE_ENTRIES) {
    const oldest = localCache.keys().next().value as string | undefined;
    if (!oldest) break;
    localCache.delete(oldest);
  }
  localCache.set(key, { value, expiresAt: now + ttlSeconds * 1_000 });
}

export function getRedis(): Redis | null {
  if (redis !== undefined) return redis;
  const url = String(process.env.REDIS_URL ?? "").trim();
  if (!url) {
    redis = null;
    warnOnce("REDIS_URL no configurada; cache, revocacion y limites usan fallback local.");
    return redis;
  }

  redis = new Redis(url, {
    lazyConnect: true,
    // Mientras no hay conexion los comandos fallan de inmediato y se usa el
    // fallback local: una peticion nunca espera a Redis.
    enableOfflineQueue: false,
    maxRetriesPerRequest: 1,
    connectTimeout: 2_000,
    // La red privada de Railway resuelve por IPv6; family 0 acepta IPv4 e IPv6.
    family: 0,
    // Antes no se reintentaba nunca: tras un corte (reinicio o mantenimiento
    // de Redis) la API quedaba en memoria local hasta reiniciarse.
    retryStrategy: (intentos) => Math.min(intentos * 500, 10_000),
  });
  redis.on("error", () => warnOnce("Redis no disponible; la API continua sin cache distribuida."));
  redis.on("ready", () => {
    if (!avisoConectado) console.log("[redis] Caché: Redis conectado.");
    else console.log("[redis] Redis reconectado.");
    avisoConectado = true;
    warned = false;
  });
  void redis.connect().catch(() => {
    warnOnce("No fue posible conectar con Redis; se aplicara degradacion local.");
  });
  return redis;
}

let avisoConectado = false;

export type EstadoRedis = "sin-configurar" | "conectado" | "desconectado";

/** Para /readyz y el log de arranque: sin detalles de conexion. */
export async function estadoRedis(timeoutMs = 1_000): Promise<EstadoRedis> {
  const client = getRedis();
  if (!client) return "sin-configurar";
  if (client.status !== "ready") return "desconectado";
  try {
    const respuesta = await Promise.race([
      client.ping(),
      new Promise<never>((_, reject) => setTimeout(() => reject(new Error("timeout")), timeoutMs)),
    ]);
    return respuesta === "PONG" ? "conectado" : "desconectado";
  } catch {
    return "desconectado";
  }
}

export async function cacheGet<T>(key: string): Promise<T | null> {
  try {
    const client = getRedis();
    if (client) {
      const value = await client.get(key);
      return value == null ? null : (JSON.parse(value) as T);
    }
  } catch {
    warnOnce("Fallo una lectura de cache; se utilizara el fallback local.");
  }

  const local = localCache.get(key);
  if (local && local.expiresAt > Date.now()) return local.value as T;
  if (local) localCache.delete(key);
  return null;
}

export async function cacheSet(key: string, value: unknown, ttlSeconds: number): Promise<void> {
  const ttl = Math.max(1, ttlSeconds);
  try {
    const client = getRedis();
    if (client) {
      await client.set(key, JSON.stringify(value), "EX", ttl);
      localCache.delete(key);
      return;
    }
  } catch {
    warnOnce("Fallo una escritura de cache; se utilizara el fallback local.");
  }
  setLocalCache(key, value, ttl);
}

export async function cacheDelete(...keys: string[]): Promise<void> {
  if (!keys.length) return;
  for (const key of keys) localCache.delete(key);
  try {
    const client = getRedis();
    if (client) await client.del(...keys);
  } catch {
    warnOnce("Fallo una invalidacion de cache; se respetara el TTL vigente.");
  }
}

export async function cached<T>(
  key: string,
  ttlSeconds: number,
  loader: () => Promise<T>,
): Promise<T> {
  const hit = await cacheGet<T>(key);
  if (hit != null) return hit;

  const existing = inFlight.get(key) as Promise<T> | undefined;
  if (existing) return existing;

  const pending = loader()
    .then(async (value) => {
      await cacheSet(key, value, ttlSeconds);
      return value;
    })
    .finally(() => inFlight.delete(key));
  inFlight.set(key, pending);
  return pending;
}

export async function incrementWindow(
  key: string,
  windowMs: number,
): Promise<{ count: number; resetMs: number } | null> {
  try {
    const client = getRedis();
    if (!client) return null;
    const result = (await client.eval(
      "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('PEXPIRE',KEYS[1],ARGV[1]); end; return {n,redis.call('PTTL',KEYS[1])}",
      1,
      key,
      String(windowMs),
    )) as [number, number];
    return { count: Number(result[0]), resetMs: Math.max(0, Number(result[1])) };
  } catch {
    warnOnce("Fallo el limitador Redis; se utilizara el limite local.");
    return null;
  }
}

export async function revokeToken(jti: string, ttlSeconds: number): Promise<void> {
  await cacheSet(`auth:revoked:${jti}`, true, ttlSeconds);
}

export async function isTokenRevoked(jti: string): Promise<boolean> {
  return (await cacheGet<boolean>(`auth:revoked:${jti}`)) === true;
}
