// src/mcp/estado.ts
//
// Interruptores y estado que se revisan en cada llamada al MCP:
// - global: MCP_ENABLED (despliegue) y ConfiguracionSistema `mcp.habilitado`
//   (en caliente, sin redeploy);
// - por herramienta: ConfiguracionSistema `mcp.herramientas.deshabilitadas`;
// - por gerente: activo, rol gerente, perfil con empresa y Gerente.mcpHabilitado;
// - por conexion: McpConexion.estado y su vida maxima.
// Todo con cache corto (Redis o local): un cambio surte efecto en <=30 s.
import type { PrismaClient } from "@prisma/client";

import { cached, cacheDelete } from "../services/RedisService";

export const CLAVE_MCP_HABILITADO = "mcp.habilitado";
export const CLAVE_HERRAMIENTAS_DESHABILITADAS = "mcp.herramientas.deshabilitadas";

const TTL_FLAGS_SEG = 15;
const TTL_ESTADO_SEG = 30;

const claveGerente = (usuarioId: string) => `mcp:gerente:v1:${usuarioId}`;
const claveConexion = (conexionId: string) => `mcp:conexion:v1:${conexionId}`;

type Flags = { habilitado: boolean; herramientasDeshabilitadas: string[] };

export async function flagsMcp(prisma: Pick<PrismaClient, "configuracionSistema">): Promise<Flags> {
  return cached("mcp:flags:v1", TTL_FLAGS_SEG, async () => {
    const filas = await prisma.configuracionSistema.findMany({
      where: { clave: { in: [CLAVE_MCP_HABILITADO, CLAVE_HERRAMIENTAS_DESHABILITADAS] } },
      select: { clave: true, valor: true },
    });
    const valor = (clave: string) => filas.find((f) => f.clave === clave)?.valor ?? "";
    return {
      habilitado: valor(CLAVE_MCP_HABILITADO).trim().toLowerCase() !== "false",
      herramientasDeshabilitadas: valor(CLAVE_HERRAMIENTAS_DESHABILITADAS)
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean),
    };
  });
}

export async function invalidarFlagsMcp(): Promise<void> {
  await cacheDelete("mcp:flags:v1");
}

export type EstadoGerente =
  | { ok: true; usuarioId: string; nombre: string; empresaId: string }
  | { ok: false; motivo: string };

/**
 * Unica regla de quien puede usar el MCP: un usuario activo, con rol gerente,
 * perfil de gerente con empresa y el acceso por IA habilitado. Ningun otro
 * rol, aunque tenga los mismos permisos en la app.
 */
export async function evaluarGerente(
  prisma: Pick<PrismaClient, "usuario">,
  usuarioId: string,
): Promise<EstadoGerente> {
  const usuario = await prisma.usuario.findUnique({
    where: { id: usuarioId },
    select: {
      id: true,
      nombre: true,
      activo: true,
      rol: true,
      gerente: { select: { empresaId: true, mcpHabilitado: true } },
    },
  });
  if (!usuario || !usuario.activo) return { ok: false, motivo: "Tu usuario no está activo en ControlApp." };
  if (String(usuario.rol).trim().toLowerCase() !== "gerente" || !usuario.gerente) {
    return { ok: false, motivo: "Solo los gerentes pueden conectar una IA a ControlApp." };
  }
  if (!usuario.gerente.empresaId) return { ok: false, motivo: "Tu perfil de gerente no tiene empresa asignada." };
  if (!usuario.gerente.mcpHabilitado) {
    return {
      ok: false,
      motivo: "Tu cuenta aún no tiene habilitada la conexión con IA. Pídesela al equipo técnico de ControlApp.",
    };
  }
  return { ok: true, usuarioId: usuario.id, nombre: usuario.nombre, empresaId: usuario.gerente.empresaId };
}

export function evaluarGerenteEnCache(prisma: Pick<PrismaClient, "usuario">, usuarioId: string) {
  return cached(claveGerente(usuarioId), TTL_ESTADO_SEG, () => evaluarGerente(prisma, usuarioId));
}

export type EstadoConexion = {
  id: string;
  usuarioId: string;
  empresaId: string;
  clienteId: string;
  clienteNombre: string;
  estado: string;
  scopes: string[];
  autorizadaEn: string;
};

export async function conexionEnCache(
  prisma: Pick<PrismaClient, "mcpConexion">,
  conexionId: string,
): Promise<EstadoConexion | null> {
  return cached(claveConexion(conexionId), TTL_ESTADO_SEG, async () => {
    const c = await prisma.mcpConexion.findUnique({
      where: { id: conexionId },
      select: {
        id: true,
        usuarioId: true,
        empresaId: true,
        clienteId: true,
        clienteNombre: true,
        estado: true,
        scopes: true,
        autorizadaEn: true,
      },
    });
    return c ? { ...c, autorizadaEn: c.autorizadaEn.toISOString() } : null;
  });
}

/** Se llama al revocar, cambiar scopes o deshabilitar a un gerente (aqui o desde la API). */
export async function invalidarEstadoMcp(params: { conexionIds?: string[]; usuarioId?: string }): Promise<void> {
  const claves = [
    ...(params.conexionIds ?? []).map(claveConexion),
    ...(params.usuarioId ? [claveGerente(params.usuarioId)] : []),
  ];
  if (claves.length) await cacheDelete(...claves);
}
