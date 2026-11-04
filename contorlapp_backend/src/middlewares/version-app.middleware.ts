// src/middlewares/version-app.middleware.ts
//
// La app Android manda su versión en cada petición (X-App-Version = versionCode,
// X-App-Plataforma = android). Si un cambio del API deja de funcionar con
// versiones viejas, se sube APP_ANDROID_VERSION_MINIMA en Railway y esas
// versiones reciben 426: la app muestra la pantalla de "Actualiza la app" y
// conserva lo que tenga guardado sin señal. Sin la variable no hace nada.
// La web no manda estas cabeceras y nunca se bloquea.
import type { RequestHandler } from "express";

const RUTAS_SIEMPRE_DISPONIBLES = new Set(["/", "/ping", "/healthz", "/readyz"]);

export function versionMinimaAndroid(): number | null {
  const valor = Number(String(process.env.APP_ANDROID_VERSION_MINIMA ?? "").trim());
  return Number.isInteger(valor) && valor > 0 ? valor : null;
}

export const exigirVersionMinimaApp: RequestHandler = (req, res, next) => {
  const minima = versionMinimaAndroid();
  if (!minima || RUTAS_SIEMPRE_DISPONIBLES.has(req.path)) {
    next();
    return;
  }
  const plataforma = String(req.headers["x-app-plataforma"] ?? "").trim().toLowerCase();
  if (plataforma !== "android") {
    next();
    return;
  }
  const version = Number(String(req.headers["x-app-version"] ?? "").trim());
  if (!Number.isInteger(version) || version >= minima) {
    next();
    return;
  }
  const mensaje = "Hay una versión nueva de ControlApp. Actualízala para seguir; lo que guardaste sin señal no se pierde.";
  res.status(426).json({
    ok: false,
    code: "APP_DESACTUALIZADA",
    message: mensaje,
    error: mensaje,
    versionMinima: minima,
  });
};
