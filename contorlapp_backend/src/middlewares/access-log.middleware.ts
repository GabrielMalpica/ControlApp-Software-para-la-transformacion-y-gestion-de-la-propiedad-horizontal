import { randomUUID } from "crypto";
import type { Request, RequestHandler } from "express";

/**
 * Registro de acceso estructurado (una linea JSON por peticion relevante).
 *
 * Antes solo se registraban errores, asi que no habia forma de reconstruir
 * quien hizo que ni desde donde (p. ej. distinguir un agente de navegador de
 * un script que llama la API directo). Se registran todas las escrituras y
 * las lecturas que fallan; las lecturas exitosas no, para no inundar el log
 * con el sondeo de notificaciones.
 *
 * El detalle de negocio (antes/despues) vive en AuditoriaEvento; aqui la ruta
 * va sin query (puede traer llaves) y con los identificadores enmascarados
 * (cedulas, NIT, ids numericos).
 */
const METODOS_LECTURA = new Set(["GET", "HEAD", "OPTIONS"]);

export function rutaParaLog(req: Pick<Request, "originalUrl">): string {
  const ruta = String(req.originalUrl ?? "").split("?")[0];
  return ruta
    .split("/")
    .map((segmento) =>
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(segmento) ||
      /\d{3,}/.test(segmento) ||
      /^(?=.*\d)[A-Za-z0-9_-]{20,}$/.test(segmento)
        ? ":id"
        : segmento,
    )
    .join("/");
}

export const registroDeAcceso: RequestHandler = (req, res, next) => {
  const inicio = process.hrtime.bigint();
  const requestId = randomUUID();
  res.setHeader("X-Request-Id", requestId);

  res.on("finish", () => {
    const metodo = req.method.toUpperCase();
    if (METODOS_LECTURA.has(metodo) && res.statusCode < 400) return;

    console.log(
      JSON.stringify({
        tipo: "acceso",
        requestId,
        metodo,
        ruta: rutaParaLog(req),
        estado: res.statusCode,
        ms: Number((process.hrtime.bigint() - inicio) / 1_000_000n),
        usuarioId: req.user?.sub ?? null,
        rol: req.user?.rol ?? null,
        ip: req.ip ?? null,
        origen: req.headers.origin ?? null,
        userAgent: String(req.headers["user-agent"] ?? "").slice(0, 200) || null,
      }),
    );
  });

  next();
};
