// src/mcp/oauth/clientes.ts
//
// Identidad de los clientes de IA. Por defecto solo se aceptan clientes que
// se identifican con un Client ID Metadata Document (CIMD) publicado en un
// origen de la lista blanca (claude.ai, chatgpt.com): un tercero no puede
// registrar "su" cliente y pedirle a un gerente que lo autorice (phishing de
// consentimiento). DCR (RFC 7591) existe como plan B y viene apagado.
import type { PrismaClient } from "@prisma/client";

import { redirectPermitido, type ConfigMcp } from "../config";

export type ClienteOAuth = {
  clientId: string;
  nombre: string;
  redirectUris: string[];
  origen: "cimd" | "dcr";
};

const TAMANO_MAXIMO_DOCUMENTO = 64 * 1024;
const TIMEOUT_DOCUMENTO_MS = 5_000;
const TTL_CACHE_MS = 60 * 60 * 1000;

const cacheDocumentos = new Map<string, { cliente: ClienteOAuth; expira: number }>();

export function limpiarCacheClientes(): void {
  cacheDocumentos.clear();
}

/**
 * True si `clientId` es una URL https que cae bajo un prefijo permitido. Se
 * compara la URL ya normalizada para que variantes con usuario, puerto o
 * caracteres codificados no se cuelen.
 */
export function esClientIdCimdPermitido(config: Pick<ConfigMcp, "clientesPermitidos">, clientId: string): boolean {
  let url: URL;
  try {
    url = new URL(clientId);
  } catch {
    return false;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.port || url.hash) return false;
  if (url.href !== clientId) return false;
  return config.clientesPermitidos.some((prefijo) => url.href.startsWith(prefijo));
}

type FetchLike = (url: string, init?: RequestInit) => Promise<Response>;

async function descargarDocumento(clientId: string, fetchImpl: FetchLike): Promise<unknown> {
  const controlador = new AbortController();
  const temporizador = setTimeout(() => controlador.abort(), TIMEOUT_DOCUMENTO_MS);
  try {
    const respuesta = await fetchImpl(clientId, {
      method: "GET",
      headers: { Accept: "application/json" },
      // Una redireccion podria llevar a otro origen: no se sigue.
      redirect: "error",
      signal: controlador.signal,
    });
    if (!respuesta.ok) throw new Error(`HTTP ${respuesta.status}`);
    const texto = await respuesta.text();
    if (texto.length > TAMANO_MAXIMO_DOCUMENTO) throw new Error("Documento demasiado grande");
    return JSON.parse(texto);
  } finally {
    clearTimeout(temporizador);
  }
}

function validarDocumento(clientId: string, documento: unknown): ClienteOAuth {
  if (!documento || typeof documento !== "object") throw new Error("Documento invalido");
  const doc = documento as Record<string, unknown>;
  if (doc.client_id !== clientId) throw new Error("El documento no corresponde a ese client_id");
  const redirectUris = Array.isArray(doc.redirect_uris)
    ? doc.redirect_uris.filter((uri): uri is string => typeof uri === "string")
    : [];
  if (!redirectUris.length) throw new Error("El documento no declara redirect_uris");
  // Solo clientes publicos con PKCE (lo que anunciamos en los metadatos). Un
  // cliente puede preferir otro metodo y aceptar "none" en la lista de
  // soportados (ChatGPT declara private_key_jwt y ["none", "private_key_jwt"]).
  const metodo = doc.token_endpoint_auth_method;
  const soportados = Array.isArray(doc.token_endpoint_auth_methods_supported)
    ? doc.token_endpoint_auth_methods_supported
    : [];
  if (metodo != null && metodo !== "none" && !soportados.includes("none")) {
    throw new Error("Metodo de autenticacion no soportado");
  }
  const nombre =
    typeof doc.client_name === "string" && doc.client_name.trim()
      ? doc.client_name.trim().slice(0, 80)
      : new URL(clientId).hostname;
  return { clientId, nombre, redirectUris, origen: "cimd" };
}

/** Resuelve un cliente por su client_id, o null si no esta permitido. */
export async function resolverCliente(
  config: ConfigMcp,
  prisma: Pick<PrismaClient, "mcpClienteRegistrado">,
  clientId: string,
  fetchImpl: FetchLike = fetch,
): Promise<ClienteOAuth | null> {
  if (!clientId) return null;

  if (esClientIdCimdPermitido(config, clientId)) {
    const enCache = cacheDocumentos.get(clientId);
    if (enCache && enCache.expira > Date.now()) return enCache.cliente;
    try {
      const cliente = validarDocumento(clientId, await descargarDocumento(clientId, fetchImpl));
      cacheDocumentos.set(clientId, { cliente, expira: Date.now() + TTL_CACHE_MS });
      return cliente;
    } catch (error) {
      console.warn("[mcp] no se pudo validar el documento del cliente", {
        clientId,
        motivo: error instanceof Error ? error.message : "desconocido",
      });
      return null;
    }
  }

  if (config.dcrHabilitado) {
    const registrado = await prisma.mcpClienteRegistrado.findUnique({ where: { clientId } });
    if (registrado) {
      return {
        clientId: registrado.clientId,
        nombre: registrado.nombre,
        redirectUris: registrado.redirectUris,
        origen: "dcr",
      };
    }
  }

  // El client_id no es secreto: queda en el log para poder ajustar
  // MCP_CLIENTES_PERMITIDOS si un cliente legitimo cambia su documento.
  console.warn("[mcp] cliente no permitido", { clientId: clientId.slice(0, 200) });
  return null;
}

/**
 * El redirect debe estar declarado por el cliente (coincidencia exacta,
 * OAuth 2.1) y ademas en la lista blanca del servidor.
 */
export function redirectValidoParaCliente(
  config: Pick<ConfigMcp, "redirectsPermitidos">,
  cliente: ClienteOAuth,
  redirectUri: string,
): boolean {
  return cliente.redirectUris.includes(redirectUri) && redirectPermitido(config, redirectUri);
}
