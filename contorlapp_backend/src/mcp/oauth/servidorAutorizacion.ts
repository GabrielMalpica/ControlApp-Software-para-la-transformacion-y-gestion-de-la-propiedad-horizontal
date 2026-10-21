// src/mcp/oauth/servidorAutorizacion.ts
//
// Servidor de autorizacion OAuth 2.1 del MCP (especificacion MCP 2026-07-28):
// - descubrimiento: RFC 9728 (recurso protegido) y RFC 8414 (servidor);
// - Authorization Code + PKCE S256 obligatorio, `resource` (RFC 8707) y
//   `iss` en la respuesta (RFC 9207);
// - clientes por Client ID Metadata Document con lista blanca; DCR apagado;
// - login con la cuenta de ControlApp en NUESTRA pagina (la IA nunca ve la
//   contrasena), solo gerentes habilitados, consentimiento por scopes;
// - refresh tokens rotativos con deteccion de reuso, revocacion (RFC 7009).
// Ver docs/mcp/arquitectura.md.
import { randomBytes, timingSafeEqual } from "crypto";
import express, { type Request, type Response, type Router } from "express";
import type { PrismaClient } from "@prisma/client";

import { contarEnVentana, distributedRateLimit } from "../../middlewares/rate-limit.middleware";
import { AuditoriaService } from "../../services/AuditoriaService";
import { NotificacionService } from "../../services/NotificacionService";
import type { ConfigMcp } from "../config";
import { evaluarGerente, flagsMcp, invalidarEstadoMcp } from "../estado";
import { SCOPES_LECTURA, TODOS_LOS_SCOPES, parsearScopes } from "../scopes";
import { redirectValidoParaCliente, resolverCliente, type ClienteOAuth } from "./clientes";
import { firmarAccessToken, hashSha256, jwkPublico, tokenAleatorio, verificarPkce } from "./tokens";
import { vistaConsentimiento, vistaError, vistaLogin } from "./vistas";

export type DependenciasOAuth = {
  config: ConfigMcp;
  prisma: PrismaClient;
  verificarCredenciales: (correo: string, contrasena: string) => Promise<{ id: string; nombre: string; rol: string }>;
  /** Para pruebas: descarga de los Client ID Metadata Documents. */
  fetchImpl?: typeof fetch;
};

const VIGENCIA_SOLICITUD_MS = 10 * 60_000;
const VIGENCIA_CODIGO_MS = 2 * 60_000;
const GRACIA_REUSO_REFRESH_MS = 30_000;

/* --------------------------------- utilidades -------------------------------- */

function iguales(a: string, b: string): boolean {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}

function cabecerasPagina(res: Response, nonce: string, origenesFormulario: string[] = []) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Pragma", "no-cache");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader(
    "Content-Security-Policy",
    [
      "default-src 'none'",
      `style-src 'nonce-${nonce}'`,
      // Chrome aplica form-action tambien a la redireccion que sigue al envio:
      // el origen del cliente (claude.ai, chatgpt.com) debe estar permitido.
      `form-action 'self' ${origenesFormulario.join(" ")}`.trim(),
      "frame-ancestors 'none'",
      "base-uri 'none'",
    ].join("; "),
  );
}

function enviarPagina(res: Response, status: number, html: (nonce: string) => string, origenes: string[] = []) {
  const nonce = randomBytes(16).toString("base64");
  cabecerasPagina(res, nonce, origenes);
  res.status(status).type("html").send(html(nonce));
}

function errorOAuth(res: Response, status: number, error: string, descripcion: string) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("Pragma", "no-cache");
  res.status(status).json({ error, error_description: descripcion });
}

function origen(url: string): string {
  try {
    return new URL(url).origin;
  } catch {
    return "";
  }
}

function host(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return url;
  }
}

/** Redireccion al cliente con codigo o error, siempre con `iss` (RFC 9207) y `state`. */
function redirigirAlCliente(
  res: Response,
  config: ConfigMcp,
  redirectUri: string,
  parametros: Record<string, string | undefined>,
) {
  const url = new URL(redirectUri);
  for (const [clave, valor] of Object.entries(parametros)) {
    if (valor !== undefined && valor !== "") url.searchParams.set(clave, valor);
  }
  url.searchParams.set("iss", config.emisor);
  res.setHeader("Cache-Control", "no-store");
  res.redirect(302, url.toString());
}

function campo(body: unknown, nombre: string): string {
  const valor = (body as Record<string, unknown> | undefined)?.[nombre];
  return typeof valor === "string" ? valor : Array.isArray(valor) ? String(valor[0] ?? "") : "";
}

/**
 * client_id de la peticion al token. Si el cliente se autentica con
 * private_key_jwt (RFC 7523) puede omitirlo y llevarlo solo en la asercion.
 * La firma no se verifica: aqui todos son clientes publicos y lo que protege
 * el canje es el codigo ligado al cliente + PKCE (o el refresh token).
 */
function clientIdDePeticion(body: unknown): string {
  const directo = campo(body, "client_id");
  if (directo) return directo;
  if (campo(body, "client_assertion_type") !== "urn:ietf:params:oauth:client-assertion-type:jwt-bearer") return "";
  const partes = campo(body, "client_assertion").split(".");
  if (partes.length !== 3 || partes[1].length > 4_096) return "";
  try {
    const carga = JSON.parse(Buffer.from(partes[1], "base64url").toString("utf8")) as Record<string, unknown>;
    return typeof carga.iss === "string" && carga.iss === carga.sub ? carga.iss : "";
  } catch {
    return "";
  }
}

async function mcpActivo(deps: DependenciasOAuth): Promise<boolean> {
  return deps.config.habilitado && (await flagsMcp(deps.prisma)).habilitado;
}

/* --------------------------------- metadatos --------------------------------- */

export function metadatosRecurso(config: ConfigMcp) {
  return {
    resource: config.recurso,
    authorization_servers: [config.emisor],
    // Lo minimo para empezar: lecturas. Las escrituras se piden con el reto
    // `insufficient_scope` o las marca el gerente al consentir.
    scopes_supported: SCOPES_LECTURA,
    bearer_methods_supported: ["header"],
    resource_name: "ControlApp",
  };
}

export function metadatosServidor(config: ConfigMcp) {
  return {
    issuer: config.emisor,
    authorization_endpoint: `${config.emisor}/oauth/authorize`,
    token_endpoint: `${config.emisor}/oauth/token`,
    revocation_endpoint: `${config.emisor}/oauth/revoke`,
    jwks_uri: `${config.emisor}/oauth/jwks`,
    ...(config.dcrHabilitado ? { registration_endpoint: `${config.emisor}/oauth/register` } : {}),
    response_types_supported: ["code"],
    response_modes_supported: ["query"],
    grant_types_supported: ["authorization_code", "refresh_token"],
    code_challenge_methods_supported: ["S256"],
    // Clientes publicos con PKCE. Claude solo usa CIMD si se anuncia "none".
    token_endpoint_auth_methods_supported: ["none"],
    revocation_endpoint_auth_methods_supported: ["none"],
    scopes_supported: TODOS_LOS_SCOPES,
    client_id_metadata_document_supported: true,
    authorization_response_iss_parameter_supported: true,
    service_documentation: `${config.emisor}/`,
  };
}

/* ---------------------------------- router ----------------------------------- */

export function crearRouterOAuth(deps: DependenciasOAuth): Router {
  const { config, prisma } = deps;
  const router = express.Router();
  const formulario = express.urlencoded({ extended: false, limit: "16kb" });
  const json = express.json({ limit: "32kb" });

  const limiteAutorizar = distributedRateLimit({
    name: "mcp:oauth:autorizar",
    windowMs: 60_000,
    limit: 30,
    key: (req) => req.ip ?? "sin-ip",
  });
  const limiteToken = distributedRateLimit({
    name: "mcp:oauth:token",
    windowMs: 60_000,
    limit: 60,
    key: (req) => req.ip ?? "sin-ip",
  });
  const limiteRegistro = distributedRateLimit({
    name: "mcp:oauth:registro",
    windowMs: 60 * 60_000,
    limit: 10,
    key: (req) => req.ip ?? "sin-ip",
  });

  const publicarMetadatosRecurso = (_req: Request, res: Response) => {
    res.setHeader("Cache-Control", "public, max-age=300");
    res.json(metadatosRecurso(config));
  };
  router.get("/.well-known/oauth-protected-resource", publicarMetadatosRecurso);
  router.get("/.well-known/oauth-protected-resource/mcp", publicarMetadatosRecurso);
  router.get("/.well-known/oauth-authorization-server", (_req, res) => {
    res.setHeader("Cache-Control", "public, max-age=300");
    res.json(metadatosServidor(config));
  });
  router.get("/oauth/jwks", (_req, res) => {
    res.setHeader("Cache-Control", "public, max-age=300");
    res.json({ keys: [jwkPublico(config)] });
  });

  /* ------------------------------- /authorize ------------------------------- */
  router.get("/oauth/authorize", limiteAutorizar, async (req, res, next) => {
    try {
      if (!(await mcpActivo(deps))) {
        enviarPagina(res, 503, (n) => vistaError(n, "La conexión con IA está desactivada en este momento."));
        return;
      }
      const q = req.query as Record<string, unknown>;
      const clientId = typeof q.client_id === "string" ? q.client_id : "";
      const redirectUri = typeof q.redirect_uri === "string" ? q.redirect_uri : "";
      const cliente = await resolverCliente(config, prisma, clientId, deps.fetchImpl);
      // Sin cliente o redirect valido NO se redirige (podria ser un atacante).
      if (!cliente) {
        enviarPagina(res, 400, (n) =>
          vistaError(n, "Este cliente de IA no está permitido. Solo se aceptan Claude y ChatGPT."),
        );
        return;
      }
      if (!redirectUri || !redirectValidoParaCliente(config, cliente, redirectUri)) {
        enviarPagina(res, 400, (n) => vistaError(n, "La dirección de retorno del cliente no está permitida."));
        return;
      }

      const state = typeof q.state === "string" ? q.state.slice(0, 500) : undefined;
      const fallar = (error: string, descripcion: string) =>
        redirigirAlCliente(res, config, redirectUri, { error, error_description: descripcion, state });

      if (q.response_type !== "code") return fallar("unsupported_response_type", "Solo se admite response_type=code.");
      if (q.code_challenge_method !== "S256") return fallar("invalid_request", "PKCE S256 es obligatorio.");
      const codeChallenge = typeof q.code_challenge === "string" ? q.code_challenge : "";
      if (!/^[A-Za-z0-9\-._~]{43,128}$/.test(codeChallenge)) return fallar("invalid_request", "code_challenge inválido.");
      const resource = typeof q.resource === "string" ? q.resource.replace(/\/+$/, "") : "";
      if (resource && resource.toLowerCase() !== config.recurso.toLowerCase()) {
        return fallar("invalid_target", "Este servidor solo emite tokens para su propio recurso MCP.");
      }
      const solicitados = parsearScopes(q.scope);

      const solicitud = await prisma.mcpSolicitudAutorizacion.create({
        data: {
          id: tokenAleatorio(24),
          clienteId: cliente.clientId,
          clienteNombre: cliente.nombre,
          redirectUri,
          state: state ?? null,
          codeChallenge,
          scopesSolicitados: solicitados.length ? solicitados : SCOPES_LECTURA,
          resource: config.recurso,
          csrf: tokenAleatorio(24),
          expiraEn: new Date(Date.now() + VIGENCIA_SOLICITUD_MS),
        },
      });
      // Limpieza oportunista de solicitudes vencidas.
      void prisma.mcpSolicitudAutorizacion
        .deleteMany({ where: { expiraEn: { lt: new Date() } } })
        .catch(() => undefined);

      enviarPagina(res, 200, (nonce) =>
        vistaLogin({
          nonce,
          solicitudId: solicitud.id,
          csrf: solicitud.csrf,
          clienteNombre: cliente.nombre,
          redirectHost: host(redirectUri),
        }),
      );
    } catch (err) {
      next(err);
    }
  });

  async function solicitudVigente(body: unknown) {
    const id = campo(body, "solicitud");
    const csrf = campo(body, "csrf");
    if (!id || !csrf) return null;
    const solicitud = await prisma.mcpSolicitudAutorizacion.findUnique({ where: { id } });
    if (!solicitud || solicitud.expiraEn.getTime() <= Date.now() || !iguales(solicitud.csrf, csrf)) return null;
    return solicitud;
  }

  /* --------------------------------- /login --------------------------------- */
  router.post("/oauth/login", limiteAutorizar, formulario, async (req, res, next) => {
    try {
      const solicitud = await solicitudVigente(req.body);
      if (!solicitud) {
        enviarPagina(res, 400, (n) =>
          vistaError(n, "La solicitud venció o no es válida. Vuelve a conectar ControlApp desde tu asistente de IA."),
        );
        return;
      }
      const correo = campo(req.body, "correo").trim().toLowerCase().slice(0, 200);
      const contrasena = campo(req.body, "contrasena");
      const reintentar = (error: string, status = 401) =>
        enviarPagina(res, status, (nonce) =>
          vistaLogin({
            nonce,
            solicitudId: solicitud.id,
            csrf: solicitud.csrf,
            clienteNombre: solicitud.clienteNombre,
            redirectHost: host(solicitud.redirectUri),
            correo,
            error,
          }),
        );

      const porIp = await contarEnVentana("mcp:login:ip", req.ip ?? "sin-ip", 60_000);
      const porCorreo = await contarEnVentana("mcp:login:correo", hashSha256(correo || "-"), 60_000);
      if (porIp.count > 5 || porCorreo.count > 3) {
        return reintentar("Demasiados intentos. Espera un minuto e inténtalo de nuevo.", 429);
      }
      if (!correo || !contrasena) return reintentar("Escribe tu correo y tu contraseña.", 400);

      let usuario: { id: string; nombre: string; rol: string };
      try {
        usuario = await deps.verificarCredenciales(correo, contrasena);
      } catch (err) {
        const status = (err as { status?: number }).status;
        return reintentar(
          status === 403 ? "Tu usuario está inactivo en ControlApp." : "Correo o contraseña incorrectos.",
        );
      }

      const gerente = await evaluarGerente(prisma, usuario.id);
      if (!gerente.ok) {
        await new AuditoriaService(prisma).registrar({
          modulo: "SEGURIDAD",
          entidad: "Usuario",
          entidadId: usuario.id,
          accion: "MCP_LOGIN_DENEGADO",
          actor: { id: usuario.id, rol: usuario.rol, nombre: usuario.nombre },
          origen: "MCP",
          descripcion: `Intento de conectar ${solicitud.clienteNombre} sin acceso por IA: ${gerente.motivo}`,
        });
        enviarPagina(res, 403, (n) => vistaError(n, gerente.motivo));
        return;
      }

      const actualizada = await prisma.mcpSolicitudAutorizacion.update({
        where: { id: solicitud.id },
        data: { usuarioId: usuario.id, csrf: tokenAleatorio(24) },
      });
      enviarPagina(
        res,
        200,
        (nonce) =>
          vistaConsentimiento({
            nonce,
            solicitudId: actualizada.id,
            csrf: actualizada.csrf,
            clienteNombre: actualizada.clienteNombre,
            redirectHost: host(actualizada.redirectUri),
            nombreGerente: gerente.nombre,
            scopesSolicitados: actualizada.scopesSolicitados,
          }),
        [origen(actualizada.redirectUri)],
      );
    } catch (err) {
      next(err);
    }
  });

  /* ------------------------------- /consentir ------------------------------- */
  router.post("/oauth/consentir", limiteAutorizar, formulario, async (req, res, next) => {
    try {
      const solicitud = await solicitudVigente(req.body);
      if (!solicitud || !solicitud.usuarioId) {
        enviarPagina(res, 400, (n) =>
          vistaError(n, "La solicitud venció o no es válida. Vuelve a conectar ControlApp desde tu asistente de IA."),
        );
        return;
      }
      await prisma.mcpSolicitudAutorizacion.delete({ where: { id: solicitud.id } });
      const state = solicitud.state ?? undefined;

      if (campo(req.body, "decision") !== "aprobar") {
        return redirigirAlCliente(res, config, solicitud.redirectUri, {
          error: "access_denied",
          error_description: "El gerente canceló la conexión.",
          state,
        });
      }
      const gerente = await evaluarGerente(prisma, solicitud.usuarioId);
      if (!gerente.ok) {
        return redirigirAlCliente(res, config, solicitud.redirectUri, {
          error: "access_denied",
          error_description: gerente.motivo,
          state,
        });
      }
      const marcados = (req.body as Record<string, unknown>)?.scope;
      const scopes = parsearScopes(Array.isArray(marcados) ? marcados.join(" ") : marcados);
      if (!scopes.length) {
        return redirigirAlCliente(res, config, solicitud.redirectUri, {
          error: "access_denied",
          error_description: "No se concedió ningún permiso.",
          state,
        });
      }

      const ahora = new Date();
      const conexion = await prisma.mcpConexion.upsert({
        where: { usuarioId_clienteId: { usuarioId: gerente.usuarioId, clienteId: solicitud.clienteId } },
        create: {
          usuarioId: gerente.usuarioId,
          empresaId: gerente.empresaId,
          clienteId: solicitud.clienteId,
          clienteNombre: solicitud.clienteNombre,
          redirectUri: solicitud.redirectUri,
          scopes,
          autorizadaEn: ahora,
        },
        update: {
          empresaId: gerente.empresaId,
          clienteNombre: solicitud.clienteNombre,
          redirectUri: solicitud.redirectUri,
          scopes,
          estado: "ACTIVA",
          autorizadaEn: ahora,
          revocadaEn: null,
          revocadaPorId: null,
          motivoRevocacion: null,
        },
      });
      // Un nuevo consentimiento reemplaza los tokens anteriores de esta conexion.
      await prisma.mcpRefreshToken.updateMany({
        where: { conexionId: conexion.id, revocadoEn: null },
        data: { revocadoEn: ahora },
      });
      await invalidarEstadoMcp({ conexionIds: [conexion.id], usuarioId: gerente.usuarioId });

      const codigo = tokenAleatorio(32);
      await prisma.mcpCodigoAutorizacion.create({
        data: {
          codigoHash: hashSha256(codigo),
          conexionId: conexion.id,
          clienteId: solicitud.clienteId,
          redirectUri: solicitud.redirectUri,
          codeChallenge: solicitud.codeChallenge,
          resource: solicitud.resource,
          scopes,
          expiraEn: new Date(Date.now() + VIGENCIA_CODIGO_MS),
        },
      });

      await new AuditoriaService(prisma).registrar({
        modulo: "SEGURIDAD",
        entidad: "McpConexion",
        entidadId: conexion.id,
        accion: "MCP_AUTORIZAR",
        empresaId: gerente.empresaId,
        actor: { id: gerente.usuarioId, rol: "gerente", nombre: gerente.nombre },
        origen: "MCP",
        descripcion: `${gerente.nombre} autorizó a ${solicitud.clienteNombre} con: ${scopes.join(", ")}.`,
        metadataJson: { clienteId: solicitud.clienteId, scopes },
      });
      await new NotificacionService(prisma)
        .crearParaUsuarios({
          usuarioIds: [gerente.usuarioId],
          tipo: "mcp_conexion",
          titulo: "Conectaste una IA a ControlApp",
          mensaje: `${solicitud.clienteNombre} puede actuar en tu nombre (${scopes.length} permiso(s)). Si no fuiste tú, revócala en Configuración → Integraciones IA.`,
          referenciaTipo: "McpConexion",
          data: { conexionId: conexion.id },
        })
        .catch(() => undefined);

      redirigirAlCliente(res, config, solicitud.redirectUri, { code: codigo, state });
    } catch (err) {
      next(err);
    }
  });

  /* ---------------------------------- /token --------------------------------- */
  async function emitirTokens(
    res: Response,
    conexion: { id: string; usuarioId: string; clienteId: string; autorizadaEn: Date },
    scopes: string[],
  ) {
    const access = firmarAccessToken(config, {
      usuarioId: conexion.usuarioId,
      clienteId: conexion.clienteId,
      conexionId: conexion.id,
      scopes,
    });
    const refresh = tokenAleatorio(32);
    const limite = conexion.autorizadaEn.getTime() + config.vidaMaximaConexionSeg * 1_000;
    await prisma.mcpRefreshToken.create({
      data: {
        conexionId: conexion.id,
        tokenHash: hashSha256(refresh),
        scopes,
        expiraEn: new Date(Math.min(Date.now() + config.inactividadRefreshSeg * 1_000, limite)),
      },
    });
    await prisma.mcpConexion.update({ where: { id: conexion.id }, data: { ultimoUsoEn: new Date() } });
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("Pragma", "no-cache");
    res.json({
      access_token: access.token,
      token_type: "Bearer",
      expires_in: config.duracionAccessTokenSeg,
      refresh_token: refresh,
      scope: scopes.join(" "),
    });
  }

  async function revocarConexion(conexionId: string, motivo: string) {
    await prisma.mcpRefreshToken.updateMany({
      where: { conexionId, revocadoEn: null },
      data: { revocadoEn: new Date() },
    });
    const conexion = await prisma.mcpConexion.update({
      where: { id: conexionId },
      data: { estado: "REVOCADA", revocadaEn: new Date(), motivoRevocacion: motivo },
      select: { usuarioId: true, clienteNombre: true },
    });
    await invalidarEstadoMcp({ conexionIds: [conexionId] });
    return conexion;
  }

  router.post("/oauth/token", limiteToken, formulario, json, async (req, res, next) => {
    try {
      if (!(await mcpActivo(deps))) {
        return errorOAuth(res, 503, "temporarily_unavailable", "La conexión con IA está desactivada.");
      }
      const grantType = campo(req.body, "grant_type");
      const clientId = clientIdDePeticion(req.body);
      const resource = campo(req.body, "resource").replace(/\/+$/, "");
      if (resource && resource.toLowerCase() !== config.recurso.toLowerCase()) {
        return errorOAuth(res, 400, "invalid_target", "Recurso desconocido.");
      }

      if (grantType === "authorization_code") {
        const codigo = campo(req.body, "code");
        const fila = codigo
          ? await prisma.mcpCodigoAutorizacion.findUnique({ where: { codigoHash: hashSha256(codigo) } })
          : null;
        if (!fila) return errorOAuth(res, 400, "invalid_grant", "Código inválido.");
        if (fila.usadoEn) {
          // Un codigo reusado indica que alguien lo intercepto: se cortan los tokens de esa conexion.
          await revocarConexion(fila.conexionId, "CODIGO_REUSADO");
          return errorOAuth(res, 400, "invalid_grant", "Código ya usado.");
        }
        if (
          fila.expiraEn.getTime() <= Date.now() ||
          fila.clienteId !== clientId ||
          fila.redirectUri !== campo(req.body, "redirect_uri") ||
          !verificarPkce(campo(req.body, "code_verifier"), fila.codeChallenge)
        ) {
          return errorOAuth(res, 400, "invalid_grant", "Código, cliente, redirect o PKCE no coinciden.");
        }
        const marcado = await prisma.mcpCodigoAutorizacion.updateMany({
          where: { codigoHash: fila.codigoHash, usadoEn: null },
          data: { usadoEn: new Date() },
        });
        if (marcado.count !== 1) return errorOAuth(res, 400, "invalid_grant", "Código ya usado.");
        const conexion = await prisma.mcpConexion.findUnique({ where: { id: fila.conexionId } });
        if (!conexion || conexion.estado !== "ACTIVA") {
          return errorOAuth(res, 400, "invalid_grant", "La conexión no está activa.");
        }
        const gerente = await evaluarGerente(prisma, conexion.usuarioId);
        if (!gerente.ok) return errorOAuth(res, 400, "invalid_grant", gerente.motivo);
        return emitirTokens(res, conexion, fila.scopes.filter((s) => conexion.scopes.includes(s)));
      }

      if (grantType === "refresh_token") {
        const token = campo(req.body, "refresh_token");
        const fila = token
          ? await prisma.mcpRefreshToken.findUnique({
              where: { tokenHash: hashSha256(token) },
              include: { conexion: true },
            })
          : null;
        if (!fila || fila.conexion.clienteId !== clientId || fila.revocadoEn) {
          return errorOAuth(res, 400, "invalid_grant", "Refresh token inválido.");
        }
        if (fila.usadoEn) {
          if (Date.now() - fila.usadoEn.getTime() > GRACIA_REUSO_REFRESH_MS) {
            const conexion = await revocarConexion(fila.conexionId, "REUSO_REFRESH");
            await new NotificacionService(prisma)
              .crearParaUsuarios({
                usuarioIds: [conexion.usuarioId],
                tipo: "mcp_alerta",
                titulo: "Revocamos una integración de IA",
                mensaje: `Detectamos el reuso de un token de ${conexion.clienteNombre} (posible robo). La revocamos; vuelve a conectarla si fuiste tú.`,
                referenciaTipo: "McpConexion",
                data: { conexionId: fila.conexionId },
              })
              .catch(() => undefined);
          }
          return errorOAuth(res, 400, "invalid_grant", "Refresh token ya usado.");
        }
        const conexion = fila.conexion;
        const vence = conexion.autorizadaEn.getTime() + config.vidaMaximaConexionSeg * 1_000;
        if (fila.expiraEn.getTime() <= Date.now() || vence <= Date.now()) {
          return errorOAuth(res, 400, "invalid_grant", "La autorización venció; vuelve a conectar ControlApp.");
        }
        if (conexion.estado !== "ACTIVA") return errorOAuth(res, 400, "invalid_grant", "La conexión fue revocada.");
        const gerente = await evaluarGerente(prisma, conexion.usuarioId);
        if (!gerente.ok) return errorOAuth(res, 400, "invalid_grant", gerente.motivo);

        let scopes = fila.scopes.filter((s) => conexion.scopes.includes(s));
        const pedidos = parsearScopes(campo(req.body, "scope"));
        if (pedidos.length) {
          if (pedidos.some((s) => !scopes.includes(s))) {
            return errorOAuth(res, 400, "invalid_scope", "No puedes ampliar permisos al renovar; vuelve a autorizar.");
          }
          scopes = pedidos;
        }
        const marcado = await prisma.mcpRefreshToken.updateMany({
          where: { id: fila.id, usadoEn: null, revocadoEn: null },
          data: { usadoEn: new Date() },
        });
        if (marcado.count !== 1) return errorOAuth(res, 400, "invalid_grant", "Refresh token ya usado.");
        return emitirTokens(res, conexion, scopes);
      }

      return errorOAuth(res, 400, "unsupported_grant_type", "Solo authorization_code y refresh_token.");
    } catch (err) {
      next(err);
    }
  });

  /* --------------------------------- /revoke -------------------------------- */
  router.post("/oauth/revoke", limiteToken, formulario, json, async (req, res, next) => {
    try {
      const token = campo(req.body, "token");
      if (token) {
        const fila = await prisma.mcpRefreshToken.findUnique({
          where: { tokenHash: hashSha256(token) },
          select: { conexionId: true, conexion: { select: { clienteId: true, estado: true } } },
        });
        const clientId = clientIdDePeticion(req.body);
        if (fila && (!clientId || fila.conexion.clienteId === clientId) && fila.conexion.estado === "ACTIVA") {
          await revocarConexion(fila.conexionId, "REVOCADA_POR_CLIENTE");
        }
      }
      // RFC 7009: responde 200 aunque el token no exista.
      res.setHeader("Cache-Control", "no-store");
      res.status(200).end();
    } catch (err) {
      next(err);
    }
  });

  /* ---------------------------- /register (DCR) ---------------------------- */
  if (config.dcrHabilitado) {
    router.post("/oauth/register", limiteRegistro, json, async (req, res, next) => {
      try {
        const body = (req.body ?? {}) as Record<string, unknown>;
        const redirectUris = Array.isArray(body.redirect_uris)
          ? body.redirect_uris.filter((u): u is string => typeof u === "string")
          : [];
        const metodo = body.token_endpoint_auth_method ?? "none";
        const prueba: ClienteOAuth = { clientId: "-", nombre: "-", redirectUris, origen: "dcr" };
        if (!redirectUris.length || !redirectUris.every((u) => redirectValidoParaCliente(config, prueba, u))) {
          return errorOAuth(res, 400, "invalid_redirect_uri", "Redirect no permitido.");
        }
        if (metodo !== "none") return errorOAuth(res, 400, "invalid_client_metadata", "Solo clientes públicos (none).");
        const nombre =
          typeof body.client_name === "string" && body.client_name.trim()
            ? body.client_name.trim().slice(0, 80)
            : host(redirectUris[0]);
        const clientId = `dcr_${tokenAleatorio(16)}`;
        await prisma.mcpClienteRegistrado.create({ data: { clientId, nombre, redirectUris } });
        res.status(201).json({
          client_id: clientId,
          client_id_issued_at: Math.floor(Date.now() / 1_000),
          client_name: nombre,
          redirect_uris: redirectUris,
          token_endpoint_auth_method: "none",
          grant_types: ["authorization_code", "refresh_token"],
          response_types: ["code"],
        });
      } catch (err) {
        next(err);
      }
    });
  }

  return router;
}
