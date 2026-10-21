// src/mcp/config.ts
//
// Configuracion del servidor MCP y de su servidor de autorizacion OAuth.
// Todo se lee del entorno (secretos de Railway) y se valida al arrancar. Sin
// MCP_ENABLED=true el servicio responde 503: nada queda expuesto por omision.
// Ver docs/mcp/despliegue.md.
import { createPrivateKey, createPublicKey, createHash, type KeyObject } from "crypto";

export type ConfigMcp = {
  habilitado: boolean;
  /** Emisor OAuth y origen publico del servicio, sin barra final (p. ej. https://mcp.dominio.com). */
  emisor: string;
  /** URI canonica del recurso protegido (RFC 8707 / RFC 9728): `${emisor}/mcp`. */
  recurso: string;
  urlMetadatosRecurso: string;
  clavePrivada: KeyObject;
  clavePublica: KeyObject;
  kid: string;
  /** Clave de 32 bytes para las referencias opacas de personas. */
  claveReferencias: Buffer;
  /** Prefijos https permitidos para el client_id de un Client ID Metadata Document. */
  clientesPermitidos: string[];
  /** Redirect URIs permitidos (exactos, o prefijo si terminan en `*`). */
  redirectsPermitidos: string[];
  dcrHabilitado: boolean;
  duracionAccessTokenSeg: number;
  inactividadRefreshSeg: number;
  vidaMaximaConexionSeg: number;
};

const CLIENTES_POR_DEFECTO = [
  // Claude (web, escritorio y movil) publica su documento en claude.ai;
  // ChatGPT (web y escritorio) en chatgpt.com. Claude Code y otros clientes
  // locales (redirect a localhost) quedan fuera por decision del propietario.
  "https://claude.ai/",
  "https://claude.com/",
  "https://chatgpt.com/",
];

const REDIRECTS_POR_DEFECTO = [
  "https://claude.ai/api/mcp/auth_callback",
  "https://claude.com/api/mcp/auth_callback",
  "https://chatgpt.com/connector_platform_oauth_redirect",
  "https://chatgpt.com/connector/oauth/*",
];

function lista(valor: string | undefined, porDefecto: string[]): string[] {
  const items = String(valor ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  return items.length ? items : porDefecto;
}

function entero(valor: string | undefined, porDefecto: number, min: number, max: number): number {
  const n = Number(valor);
  if (!Number.isFinite(n)) return porDefecto;
  return Math.min(Math.max(Math.round(n), min), max);
}

/** Acepta el PEM con saltos reales o escapados como `\n` (formato de Railway). */
function pem(valor: string): string {
  return valor.includes("\\n") ? valor.replace(/\\n/g, "\n") : valor;
}

function quitarBarraFinal(url: string): string {
  return url.replace(/\/+$/, "");
}

export class ErrorConfigMcp extends Error {}

export function leerConfigMcp(env: NodeJS.ProcessEnv = process.env): ConfigMcp {
  const habilitado = String(env.MCP_ENABLED ?? "").trim().toLowerCase() === "true";

  const emisorRaw = String(env.MCP_ISSUER ?? "").trim();
  if (!emisorRaw) throw new ErrorConfigMcp("Falta MCP_ISSUER (p. ej. https://mcp.tu-dominio.com).");
  let emisorUrl: URL;
  try {
    emisorUrl = new URL(emisorRaw);
  } catch {
    throw new ErrorConfigMcp("MCP_ISSUER no es una URL valida.");
  }
  const esLocal = ["localhost", "127.0.0.1"].includes(emisorUrl.hostname);
  if (emisorUrl.protocol !== "https:" && !(esLocal && env.NODE_ENV !== "production")) {
    throw new ErrorConfigMcp("MCP_ISSUER debe usar https (OAuth 2.1 exige HTTPS).");
  }
  if (emisorUrl.search || emisorUrl.hash) {
    throw new ErrorConfigMcp("MCP_ISSUER no puede llevar query ni fragmento.");
  }
  const emisor = quitarBarraFinal(emisorUrl.toString());

  const clavePem = String(env.MCP_JWT_PRIVATE_KEY ?? "").trim();
  if (!clavePem) {
    throw new ErrorConfigMcp(
      "Falta MCP_JWT_PRIVATE_KEY (clave EC P-256 en PEM; generala con `npm run mcp:claves`).",
    );
  }
  let clavePrivada: KeyObject;
  try {
    clavePrivada = createPrivateKey(pem(clavePem));
  } catch {
    throw new ErrorConfigMcp("MCP_JWT_PRIVATE_KEY no es una clave privada PEM valida.");
  }
  if (
    clavePrivada.asymmetricKeyType !== "ec" ||
    clavePrivada.asymmetricKeyDetails?.namedCurve !== "prime256v1"
  ) {
    throw new ErrorConfigMcp("MCP_JWT_PRIVATE_KEY debe ser una clave EC P-256 (ES256).");
  }
  const clavePublica = createPublicKey(clavePrivada);
  const kid =
    String(env.MCP_JWT_KID ?? "").trim() ||
    createHash("sha256")
      .update(clavePublica.export({ type: "spki", format: "der" }))
      .digest("base64url")
      .slice(0, 16);

  const claveRefRaw = String(env.MCP_REF_KEY ?? "").trim();
  const claveReferencias = Buffer.from(claveRefRaw, "base64");
  if (claveReferencias.length !== 32) {
    throw new ErrorConfigMcp("MCP_REF_KEY debe ser 32 bytes en base64 (`npm run mcp:claves`).");
  }

  const clientesPermitidos = lista(env.MCP_CLIENTES_PERMITIDOS, CLIENTES_POR_DEFECTO);
  for (const prefijo of clientesPermitidos) {
    if (!prefijo.startsWith("https://")) {
      throw new ErrorConfigMcp(`MCP_CLIENTES_PERMITIDOS solo admite prefijos https: ${prefijo}`);
    }
  }

  return {
    habilitado,
    emisor,
    recurso: `${emisor}/mcp`,
    urlMetadatosRecurso: `${emisor}/.well-known/oauth-protected-resource/mcp`,
    clavePrivada,
    clavePublica,
    kid,
    claveReferencias,
    clientesPermitidos,
    redirectsPermitidos: lista(env.MCP_REDIRECTS_PERMITIDOS, REDIRECTS_POR_DEFECTO),
    dcrHabilitado: String(env.MCP_DCR_HABILITADO ?? "").trim().toLowerCase() === "true",
    duracionAccessTokenSeg: entero(env.MCP_ACCESS_TOKEN_MINUTOS, 10, 2, 60) * 60,
    inactividadRefreshSeg: entero(env.MCP_REFRESH_INACTIVIDAD_DIAS, 7, 1, 30) * 86_400,
    vidaMaximaConexionSeg: entero(env.MCP_CONEXION_MAX_DIAS, 30, 1, 90) * 86_400,
  };
}

/** Coincidencia de redirect: exacta, o por prefijo si la entrada termina en `*`. */
export function redirectPermitido(config: Pick<ConfigMcp, "redirectsPermitidos">, uri: string): boolean {
  return config.redirectsPermitidos.some((permitido) =>
    permitido.endsWith("*") ? uri.startsWith(permitido.slice(0, -1)) : uri === permitido,
  );
}
