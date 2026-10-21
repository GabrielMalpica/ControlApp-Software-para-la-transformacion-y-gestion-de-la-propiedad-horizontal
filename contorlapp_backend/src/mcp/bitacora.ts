// src/mcp/bitacora.ts
//
// Registro de cada herramienta ejecutada (McpInvocacion): quien autorizo
// (usuario), que integracion (conexion) y que cliente, que herramienta, con
// que parametros (redactados) y con que resultado. Nunca guarda tokens,
// contrasenas, cedulas ni datos de contacto completos.
import type { Prisma, PrismaClient } from "@prisma/client";

import { contarEnVentana } from "../middlewares/rate-limit.middleware";
import { NotificacionService } from "../services/NotificacionService";
import { hashCanonico } from "./confirmaciones";
import { invalidarEstadoMcp } from "./estado";

const CAMPOS_REDACTADOS = new Set(["cedula", "telefono", "correo", "contrasena", "token", "fechaNacimiento"]);
const LIMITE_TEXTO = 200;

export type RegistroInvocacion = {
  conexionId: string;
  usuarioId: string;
  empresaId: string;
  clienteId: string;
  herramienta: string;
  nivelRiesgo: string;
  resultado: "OK" | "PREVIEW" | "CONFIRMADO" | "DENEGADO" | "ERROR" | "LIMITE" | "DESHABILITADA";
  codigo?: string | null;
  mensaje?: string | null;
  parametros: unknown;
  entidades?: Array<{ tipo: string; id: string | number }>;
  confirmacionId?: string | null;
  latenciaMs: number;
  ip?: string | null;
  userAgent?: string | null;
};

export function redactar(valor: unknown, profundidad = 0): unknown {
  if (profundidad > 6) return "[...]";
  if (typeof valor === "string") return valor.length > LIMITE_TEXTO ? `${valor.slice(0, LIMITE_TEXTO)}…` : valor;
  if (Array.isArray(valor)) return valor.slice(0, 60).map((v) => redactar(v, profundidad + 1));
  if (valor && typeof valor === "object") {
    return Object.fromEntries(
      Object.entries(valor as Record<string, unknown>).map(([k, v]) => [
        k,
        CAMPOS_REDACTADOS.has(k) ? "[redactado]" : redactar(v, profundidad + 1),
      ]),
    );
  }
  return valor;
}

/** Recorta la IP (ultimo octeto / ultimos grupos): basta para investigar sin guardarla completa. */
export function ipTruncada(ip: string | null | undefined): string | null {
  if (!ip) return null;
  const limpia = ip.replace(/^::ffff:/, "");
  if (/^\d+\.\d+\.\d+\.\d+$/.test(limpia)) return limpia.replace(/\.\d+$/, ".0");
  const grupos = limpia.split(":");
  return grupos.length > 3 ? `${grupos.slice(0, 3).join(":")}::` : limpia;
}

const UMBRAL_DENEGADOS = 20;
const VENTANA_DENEGADOS_MS = 5 * 60_000;

export async function registrarInvocacion(prisma: PrismaClient, registro: RegistroInvocacion): Promise<void> {
  try {
    await prisma.mcpInvocacion.create({
      data: {
        conexionId: registro.conexionId,
        usuarioId: registro.usuarioId,
        empresaId: registro.empresaId,
        clienteId: registro.clienteId,
        herramienta: registro.herramienta,
        nivelRiesgo: registro.nivelRiesgo,
        resultado: registro.resultado,
        codigo: registro.codigo ?? null,
        mensaje: registro.mensaje ? registro.mensaje.slice(0, 500) : null,
        parametrosHash: hashCanonico(registro.parametros ?? null),
        parametrosRedactados: (redactar(registro.parametros ?? null) ?? undefined) as Prisma.InputJsonValue,
        entidadesAfectadas: registro.entidades?.length
          ? (registro.entidades.map((e) => ({ tipo: e.tipo, id: String(e.id) })) as Prisma.InputJsonValue)
          : undefined,
        confirmacionId: registro.confirmacionId ?? null,
        latenciaMs: Math.max(0, Math.round(registro.latenciaMs)),
        ip: ipTruncada(registro.ip),
        userAgent: registro.userAgent ? registro.userAgent.slice(0, 200) : null,
      },
    });
  } catch (error) {
    // La bitacora no debe tumbar la respuesta, pero si queda en el log.
    console.error("[mcp] no se pudo registrar la invocacion", {
      herramienta: registro.herramienta,
      motivo: error instanceof Error ? error.message : "desconocido",
    });
  }

  if (registro.resultado === "DENEGADO") {
    await vigilarDenegaciones(prisma, registro).catch(() => undefined);
  }
}

/**
 * Muchas denegaciones seguidas (ids ajenos, permisos que no tiene) no son un
 * uso normal: se suspende la conexion y se avisa al gerente.
 */
async function vigilarDenegaciones(prisma: PrismaClient, registro: RegistroInvocacion) {
  const { count } = await contarEnVentana("mcp:denegados", registro.conexionId, VENTANA_DENEGADOS_MS);
  if (count !== UMBRAL_DENEGADOS) return;
  await prisma.mcpConexion.updateMany({
    where: { id: registro.conexionId, estado: "ACTIVA" },
    data: { estado: "SUSPENDIDA", motivoRevocacion: "DENEGACIONES_REPETIDAS", revocadaEn: new Date() },
  });
  await prisma.mcpRefreshToken.updateMany({
    where: { conexionId: registro.conexionId, revocadoEn: null },
    data: { revocadoEn: new Date() },
  });
  await invalidarEstadoMcp({ conexionIds: [registro.conexionId] });
  await new NotificacionService(prisma).crearParaUsuarios({
    usuarioIds: [registro.usuarioId],
    tipo: "mcp_alerta",
    titulo: "Suspendimos una integración de IA",
    mensaje:
      "Una IA conectada a tu cuenta intentó muchas operaciones no permitidas en pocos minutos. La suspendimos por seguridad; revísala en Configuración → Integraciones IA.",
    referenciaTipo: "McpConexion",
    data: { conexionId: registro.conexionId },
  });
}
