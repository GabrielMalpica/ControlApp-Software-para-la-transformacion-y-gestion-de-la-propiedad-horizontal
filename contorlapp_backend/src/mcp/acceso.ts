// src/mcp/acceso.ts
//
// Autenticacion de cada peticion a /mcp. El cliente, la IA y los parametros
// nunca aportan identidad: todo sale del access token (firmado por nosotros,
// para este recurso) y de la BD (conexion activa, gerente vigente y
// habilitado, scopes que siguen concedidos).
import type { PrismaClient } from "@prisma/client";

import type { ConfigMcp } from "./config";
import { conexionEnCache, evaluarGerenteEnCache } from "./estado";
import { verificarAccessToken } from "./oauth/tokens";
import { SCOPES_LECTURA } from "./scopes";

export type DatosAcceso = {
  conexionId: string;
  usuarioId: string;
  nombre: string;
  empresaId: string;
  clienteId: string;
  clienteNombre: string;
  /** Scopes del token que siguen concedidos en la conexion (sin expandir). */
  scopes: string[];
};

/** Forma de AuthInfo del SDK MCP (pasa tal cual al factory de servidores). */
export type InfoAutenticacion = {
  token: string;
  clientId: string;
  scopes: string[];
  expiresAt: number;
  resource: URL;
  resourceMetadataUrl: string;
  extra: { acceso: DatosAcceso };
};

export type ResultadoAcceso =
  | { ok: true; authInfo: InfoAutenticacion }
  | { ok: false; status: 401; wwwAuthenticate: string; error: string; descripcion: string };

export function retoAutenticacion(config: ConfigMcp, error?: { codigo: string; descripcion: string }): string {
  const partes = [`resource_metadata="${config.urlMetadatosRecurso}"`, `scope="${SCOPES_LECTURA.join(" ")}"`];
  if (error) {
    partes.unshift(`error="${error.codigo}"`);
    partes.push(`error_description="${error.descripcion.replace(/"/g, "'")}"`);
  }
  return `Bearer ${partes.join(", ")}`;
}

function rechazo(config: ConfigMcp, descripcion: string, conToken = true): ResultadoAcceso {
  return {
    ok: false,
    status: 401,
    wwwAuthenticate: retoAutenticacion(config, conToken ? { codigo: "invalid_token", descripcion } : undefined),
    error: "invalid_token",
    descripcion,
  };
}

export async function autenticarPeticionMcp(
  config: ConfigMcp,
  prisma: PrismaClient,
  autorizacion: string | undefined,
): Promise<ResultadoAcceso> {
  if (!autorizacion || !autorizacion.startsWith("Bearer ")) {
    return rechazo(config, "Falta el token de acceso.", false);
  }
  const token = autorizacion.slice("Bearer ".length).trim();

  let claims;
  try {
    claims = verificarAccessToken(config, token);
  } catch {
    return rechazo(config, "Token inválido o vencido.");
  }

  const conexion = await conexionEnCache(prisma, claims.cid);
  if (
    !conexion ||
    conexion.estado !== "ACTIVA" ||
    conexion.usuarioId !== claims.sub ||
    conexion.clienteId !== claims.client_id
  ) {
    return rechazo(config, "La conexión fue revocada o no existe.");
  }
  const vence = new Date(conexion.autorizadaEn).getTime() + config.vidaMaximaConexionSeg * 1_000;
  if (vence <= Date.now()) return rechazo(config, "La autorización venció; vuelve a conectar ControlApp.");

  const gerente = await evaluarGerenteEnCache(prisma, claims.sub);
  if (!gerente.ok) return rechazo(config, gerente.motivo);
  if (gerente.empresaId !== conexion.empresaId) return rechazo(config, "La conexión ya no corresponde a tu empresa.");

  const delToken = claims.scope.split(" ").filter(Boolean);
  // Si el gerente redujo permisos en el panel, aplica de inmediato.
  const scopes = delToken.filter((s) => conexion.scopes.includes(s));

  return {
    ok: true,
    authInfo: {
      token,
      clientId: claims.client_id,
      scopes,
      expiresAt: claims.exp,
      resource: new URL(config.recurso),
      resourceMetadataUrl: config.urlMetadatosRecurso,
      extra: {
        acceso: {
          conexionId: conexion.id,
          usuarioId: gerente.usuarioId,
          nombre: gerente.nombre,
          empresaId: gerente.empresaId,
          clienteId: conexion.clienteId,
          clienteNombre: conexion.clienteNombre,
          scopes,
        },
      },
    },
  };
}
