import type { Request } from "express";
import { distributedRateLimit } from "./rate-limit.middleware";

const TASK_CLOSING_PATHS = [
  /^\/supervisor\/tareas\/\d+\/cerrar\/?$/,
  /^\/operario\/operarios\/\d+\/tareas\/\d+\/cerrar\/?$/,
];

export function isTaskClosingRequest(
  req: Pick<Request, "method" | "path">,
): boolean {
  return (
    req.method.toUpperCase() === "POST" &&
    TASK_CLOSING_PATHS.some((pattern) => pattern.test(req.path))
  );
}

/** Evita que solicitudes sin autenticar puedan abusar de la excepcion global. */
export const taskClosingIpRateLimit = distributedRateLimit({
  name: "cronograma:cierre-tarea:ip",
  windowMs: 15 * 60_000,
  limit: 10_000,
  key: (req) => req.ip ?? "sin-ip",
});

/**
 * Los cierres masivos del cronograma pueden concentrar muchas solicitudes.
 * Se mantiene una barrera defensiva, pero 100 veces mas amplia que el limite
 * general de cargas multipart y aislada por usuario autenticado.
 */
export const taskClosingRateLimit = distributedRateLimit({
  name: "cronograma:cierre-tarea",
  windowMs: 15 * 60_000,
  limit: 2_000,
  key: (req) => req.user?.sub ?? req.ip ?? "sin-identidad",
  message:
    "Se alcanzo temporalmente el limite de cierres de tareas. Intenta nuevamente en unos minutos",
});
