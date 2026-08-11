import { Request, RequestHandler } from "express";
import { incrementWindow } from "../services/RedisService";

type RateLimitOptions = {
  name: string;
  windowMs: number;
  limit: number;
  key: (req: Request) => string;
  message?: string;
};

const localWindows = new Map<string, { count: number; expiresAt: number }>();
const MAX_LOCAL_WINDOWS = 10_000;

function pruneLocalWindows(now: number) {
  if (localWindows.size < MAX_LOCAL_WINDOWS) return;
  for (const [key, value] of localWindows) {
    if (value.expiresAt <= now) localWindows.delete(key);
  }
  while (localWindows.size >= MAX_LOCAL_WINDOWS) {
    const oldest = localWindows.keys().next().value as string | undefined;
    if (!oldest) break;
    localWindows.delete(oldest);
  }
}

function localIncrement(key: string, windowMs: number) {
  const now = Date.now();
  pruneLocalWindows(now);
  const current = localWindows.get(key);
  if (!current || current.expiresAt <= now) {
    const fresh = { count: 1, expiresAt: now + windowMs };
    localWindows.set(key, fresh);
    return { count: fresh.count, resetMs: windowMs };
  }
  current.count += 1;
  return { count: current.count, resetMs: current.expiresAt - now };
}

export function distributedRateLimit(options: RateLimitOptions): RequestHandler {
  return async (req, res, next) => {
    try {
      const identity = options.key(req).trim().toLowerCase() || "anonimo";
      const key = `ratelimit:${options.name}:${identity}`;
      const state =
        (await incrementWindow(key, options.windowMs)) ?? localIncrement(key, options.windowMs);

      res.setHeader("RateLimit-Limit", String(options.limit));
      res.setHeader("RateLimit-Remaining", String(Math.max(0, options.limit - state.count)));
      res.setHeader("RateLimit-Reset", String(Math.ceil(state.resetMs / 1000)));
      if (state.count > options.limit) {
        res.status(429).json({
          ok: false,
          message: options.message ?? "Demasiadas solicitudes. Intenta nuevamente mas tarde",
        });
        return;
      }
      next();
    } catch (error) {
      next(error);
    }
  };
}
