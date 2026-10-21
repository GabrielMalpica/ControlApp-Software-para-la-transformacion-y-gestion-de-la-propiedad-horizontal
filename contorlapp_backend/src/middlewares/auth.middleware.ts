import { Request, RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { isTokenRevoked } from "../services/RedisService";
import { estadoSesionUsuario, motivoSesionInvalida } from "../services/SesionService";
import { verificarTokenSesion, type AuthPayload } from "../utils/jwtSesion";

export type { AuthPayload } from "../utils/jwtSesion";

function isPublicRequest(method: string, path: string): boolean {
  if (method === "GET" && (path === "/" || path === "/ping")) return true;
  if (
    method === "POST" &&
    (path === "/auth/login" || path === "/auth/recuperar-contrasena")
  ) {
    return true;
  }

  // Renovacion de la sesion web: se autentica con la cookie HttpOnly, no con
  // Bearer (el token en memoria ya pudo vencer). El logout tambien llega con
  // token vencido y debe poder cerrar la cookie; cada uno valida por su cuenta.
  if (method === "POST" && (path === "/auth/refresh" || path === "/auth/logout")) {
    return true;
  }

  if (
    method === "GET" &&
    (path === "/commerce/catalogo" || path.startsWith("/commerce/catalogo/"))
  ) {
    return true;
  }

  // Sin Bearer: WooCommerce no manda un JWT de ControlApp. Se autentica con
  // su propia firma HMAC (ver CommerceWebhookController), verificada dentro
  // del handler -esto solo lo exime del guard generico de Bearer token.
  if (method === "POST" && path === "/commerce/webhooks/woocommerce") return true;

  // Plugin puente controlapp-archivos-drive (formularios de la pagina web):
  // firma HMAC con el hash del archivo (ver web-archivos-hmac.middleware).
  if (method === "POST" && path === "/commerce/web/archivos") return true;

  // Factus Pay no manda Bearer: autentica con la llave del query string,
  // verificada en FactusWebhookService (y el aviso nunca confirma un pago
  // por si solo: se verifica por API).
  if (method === "POST" && path === "/commerce/webhooks/factus-pay") return true;

  // Plugin controlapp-factus-pay de la tienda (cobros, saldos de servicios y
  // consulta de mora): se autentica con HMAC + nonce (ver requirePagosWooHmac
  // en cada ruta de Commerce.ts), no con un JWT.
  return (
    (method === "POST" || method === "GET") &&
    path.startsWith("/commerce/pagos/woo/")
  );
}

/**
 * Con una contrasena temporal pendiente el token solo sirve para cambiarla
 * (y para leer la sesion o cerrarla). Antes esto solo lo hacia cumplir el
 * frontend: por API se podia usar la cuenta sin cambiarla.
 */
function permitidaConCambioPendiente(req: Request): boolean {
  const path = req.originalUrl.split("?")[0];
  const method = req.method.toUpperCase();
  if (method === "GET" && path === "/auth/me") return true;
  return (
    method === "POST" &&
    ["/auth/cambiar-contrasena-inicial", "/auth/logout", "/auth/logout-todas"].includes(path)
  );
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthPayload;
      // Cuerpo crudo capturado por el verify() de express.json() en index.ts
      // -lo necesita el webhook de WooCommerce para validar su firma HMAC.
      rawBody?: Buffer;
    }
  }
}

function bearer(req: Request): string | null {
  const header = req.headers.authorization;
  if (!header || !header.startsWith("Bearer ")) return null;
  return header.replace("Bearer ", "").trim() || null;
}

export const authRequired: RequestHandler = async (req, res, next) => {
  // Varios routers declaran authRequired ademas del cierre global: si ya se
  // valido en esta peticion, no se repite.
  if (req.user) {
    next();
    return;
  }

  const token = bearer(req);
  if (!token) {
    res.status(401).json({ message: "Token requerido" });
    return;
  }

  let payload: AuthPayload;
  try {
    payload = verificarTokenSesion(token);
  } catch {
    res.status(401).json({ message: "Token inválido o expirado" });
    return;
  }

  try {
    if (payload.jti && (await isTokenRevoked(payload.jti))) {
      res.status(401).json({ message: "Token revocado" });
      return;
    }

    const estado = await estadoSesionUsuario(prisma, payload.sub);
    const motivo = motivoSesionInvalida(payload, estado);
    if (motivo) {
      res.status(401).json({ message: motivo, code: "SESION_INVALIDA" });
      return;
    }

    if (estado?.requiereCambioContrasena && !permitidaConCambioPendiente(req)) {
      res.status(403).json({
        message: "Debes cambiar tu contraseña temporal antes de continuar.",
        code: "CAMBIO_CONTRASENA_REQUERIDO",
      });
      return;
    }

    req.user = payload;
    next();
  } catch (error) {
    next(error);
  }
};

export const authOptional: RequestHandler = async (req, _res, next) => {
  if (req.user) {
    next();
    return;
  }

  const token = bearer(req);
  if (!token) {
    next();
    return;
  }

  try {
    const payload = verificarTokenSesion(token);
    const revocado = payload.jti ? await isTokenRevoked(payload.jti) : false;
    const estado = revocado ? null : await estadoSesionUsuario(prisma, payload.sub);
    req.user =
      !revocado && !motivoSesionInvalida(payload, estado) ? payload : undefined;
  } catch {
    req.user = undefined;
  }

  next();
};

/**
 * Cierre defensivo global. Las rutas siguen declarando autorizacion por rol y
 * permiso; esta allowlist evita que una ruta nueva quede publica por omision.
 */
export const authRequiredUnlessPublic: RequestHandler = (req, res, next) => {
  if (isPublicRequest(req.method.toUpperCase(), req.path)) {
    next();
    return;
  }

  authRequired(req, res, next);
};
