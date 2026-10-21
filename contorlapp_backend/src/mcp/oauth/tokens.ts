// src/mcp/oauth/tokens.ts
//
// Tokens del MCP. Firmados con una clave EC propia (ES256), nunca con
// JWT_SECRET: un token de la API no sirve aqui ni uno de aqui en la API
// (distinta clave, emisor y audiencia). Ver docs/mcp/arquitectura.md.
import { createHash, randomBytes, randomUUID, timingSafeEqual } from "crypto";
import jwt from "jsonwebtoken";

import type { ConfigMcp } from "../config";

export type ClaimsAccessToken = {
  iss: string;
  aud: string;
  sub: string;
  client_id: string;
  /** Conexion (McpConexion.id) que emitio el token. */
  cid: string;
  scope: string;
  jti: string;
  iat: number;
  exp: number;
};

export function tokenAleatorio(bytes = 32): string {
  return randomBytes(bytes).toString("base64url");
}

export function hashSha256(valor: string): string {
  return createHash("sha256").update(valor).digest("hex");
}

export function firmarAccessToken(
  config: ConfigMcp,
  datos: { usuarioId: string; clienteId: string; conexionId: string; scopes: string[] },
): { token: string; expiraEn: number } {
  const ahora = Math.floor(Date.now() / 1_000);
  const exp = ahora + config.duracionAccessTokenSeg;
  const token = jwt.sign(
    {
      client_id: datos.clienteId,
      cid: datos.conexionId,
      scope: datos.scopes.join(" "),
    },
    config.clavePrivada,
    {
      algorithm: "ES256",
      // RFC 9068: tipo "at+jwt" para que no se confunda con un ID token.
      header: { alg: "ES256", kid: config.kid, typ: "at+jwt" },
      issuer: config.emisor,
      audience: config.recurso,
      subject: datos.usuarioId,
      jwtid: randomUUID(),
      expiresIn: config.duracionAccessTokenSeg,
    },
  );
  return { token, expiraEn: exp };
}

/** Lanza si la firma, el algoritmo, el emisor, la audiencia o la fecha no son validos. */
export function verificarAccessToken(config: ConfigMcp, token: string): ClaimsAccessToken {
  const payload = jwt.verify(token, config.clavePublica, {
    algorithms: ["ES256"],
    issuer: config.emisor,
    audience: config.recurso,
  });
  if (
    typeof payload === "string" ||
    typeof payload.sub !== "string" ||
    typeof (payload as { cid?: unknown }).cid !== "string" ||
    typeof (payload as { client_id?: unknown }).client_id !== "string" ||
    typeof payload.exp !== "number"
  ) {
    throw new Error("Token sin los datos esperados");
  }
  return payload as unknown as ClaimsAccessToken;
}

/** PKCE S256 (RFC 7636): BASE64URL(SHA256(code_verifier)) === code_challenge. */
export function verificarPkce(codeVerifier: string, codeChallenge: string): boolean {
  if (!/^[A-Za-z0-9\-._~]{43,128}$/.test(codeVerifier)) return false;
  const calculado = createHash("sha256").update(codeVerifier).digest("base64url");
  const a = Buffer.from(calculado);
  const b = Buffer.from(codeChallenge);
  return a.length === b.length && timingSafeEqual(a, b);
}

/** JWK publico (RFC 7517) para /oauth/jwks. */
export function jwkPublico(config: ConfigMcp) {
  const jwk = config.clavePublica.export({ format: "jwk" }) as Record<string, unknown>;
  return { ...jwk, kid: config.kid, use: "sig", alg: "ES256" };
}
