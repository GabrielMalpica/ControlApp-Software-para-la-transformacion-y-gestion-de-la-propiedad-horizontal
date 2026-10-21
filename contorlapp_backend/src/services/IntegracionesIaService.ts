// src/services/IntegracionesIaService.ts
//
// Panel "Configuración → Integraciones IA" (solo gerentes): conexiones de
// clientes de IA por MCP, su actividad, revocacion, reduccion de permisos y
// aprobacion de operaciones de alto riesgo. Ver docs/mcp/arquitectura.md.
import type { PrismaClient } from "@prisma/client";

import { ESTADOS_CONFIRMACION, VIGENCIA_TRAS_APROBAR_MS } from "../mcp/confirmaciones";
import { invalidarEstadoMcp } from "../mcp/estado";
import { CATALOGO_SCOPES, parsearScopes } from "../mcp/scopes";
import { AuditoriaService } from "./AuditoriaService";

type HttpError = Error & { status: number };

function httpError(status: number, mensaje: string): HttpError {
  return Object.assign(new Error(mensaje), { status });
}

export type ActorPanel = { id: string; nombre: string | null; empresaId: string };

export class IntegracionesIaService {
  constructor(private readonly prisma: PrismaClient) {}

  private auditoria(actor: ActorPanel, accion: string, entidadId: string, descripcion: string, metadata?: unknown) {
    return new AuditoriaService(this.prisma).registrar({
      modulo: "SEGURIDAD",
      entidad: "McpConexion",
      entidadId,
      accion,
      empresaId: actor.empresaId,
      actor: { id: actor.id, rol: "gerente", nombre: actor.nombre },
      descripcion,
      metadataJson: metadata,
    });
  }

  async configuracion(actor: ActorPanel) {
    const gerente = await this.prisma.gerente.findUnique({
      where: { id: actor.id },
      select: { mcpHabilitado: true },
    });
    return {
      urlServidor: String(process.env.MCP_PUBLIC_URL ?? "").trim() || null,
      habilitadoParaMi: Boolean(gerente?.mcpHabilitado),
      permisos: CATALOGO_SCOPES.map((s) => ({ scope: s.scope, titulo: s.titulo, descripcion: s.descripcion, nivel: s.nivel })),
    };
  }

  async listar(actor: ActorPanel) {
    const conexiones = await this.prisma.mcpConexion.findMany({
      where: { empresaId: actor.empresaId },
      select: {
        id: true,
        usuarioId: true,
        clienteNombre: true,
        clienteId: true,
        scopes: true,
        estado: true,
        creadaEn: true,
        autorizadaEn: true,
        ultimoUsoEn: true,
        revocadaEn: true,
        motivoRevocacion: true,
        usuario: { select: { nombre: true } },
      },
      orderBy: [{ estado: "asc" }, { ultimoUsoEn: "desc" }],
      take: 200,
    });
    return conexiones.map((c) => ({
      id: c.id,
      propia: c.usuarioId === actor.id,
      gerente: c.usuario.nombre,
      cliente: c.clienteNombre,
      clienteHost: (() => {
        try {
          return new URL(c.clienteId).host;
        } catch {
          return c.clienteId;
        }
      })(),
      permisos: c.scopes,
      estado: c.estado,
      creadaEn: c.creadaEn,
      autorizadaEn: c.autorizadaEn,
      ultimoUsoEn: c.ultimoUsoEn,
      revocadaEn: c.revocadaEn,
      motivoRevocacion: c.motivoRevocacion,
    }));
  }

  private async conexionDeEmpresa(actor: ActorPanel, conexionId: string) {
    const conexion = await this.prisma.mcpConexion.findFirst({
      where: { id: conexionId, empresaId: actor.empresaId },
    });
    if (!conexion) throw httpError(404, "Integración no encontrada.");
    return conexion;
  }

  /**
   * Cualquier gerente de la empresa puede revocar cualquier conexion (respuesta
   * a incidentes); el efecto es inmediato para los refresh y <=30 s para los
   * access tokens vigentes.
   */
  async revocar(actor: ActorPanel, conexionId: string) {
    const conexion = await this.conexionDeEmpresa(actor, conexionId);
    if (conexion.estado === "REVOCADA") return { ok: true };
    await this.prisma.$transaction([
      this.prisma.mcpRefreshToken.updateMany({
        where: { conexionId: conexion.id, revocadoEn: null },
        data: { revocadoEn: new Date() },
      }),
      this.prisma.mcpConexion.update({
        where: { id: conexion.id },
        data: { estado: "REVOCADA", revocadaEn: new Date(), revocadaPorId: actor.id, motivoRevocacion: "REVOCADA_EN_PANEL" },
      }),
      this.prisma.mcpConfirmacion.updateMany({
        where: {
          conexionId: conexion.id,
          estado: { in: [ESTADOS_CONFIRMACION.PENDIENTE, ESTADOS_CONFIRMACION.PENDIENTE_APROBACION, ESTADOS_CONFIRMACION.APROBADA] },
        },
        data: { estado: ESTADOS_CONFIRMACION.RECHAZADA, decididaPorId: actor.id, decididaEn: new Date() },
      }),
    ]);
    await invalidarEstadoMcp({ conexionIds: [conexion.id] });
    await this.auditoria(actor, "MCP_REVOCAR", conexion.id, `${actor.nombre ?? actor.id} revocó la integración ${conexion.clienteNombre}.`);
    return { ok: true };
  }

  async revocarTodasLasMias(actor: ActorPanel) {
    const activas = await this.prisma.mcpConexion.findMany({
      where: { usuarioId: actor.id, empresaId: actor.empresaId, estado: { in: ["ACTIVA", "SUSPENDIDA"] } },
      select: { id: true },
    });
    for (const conexion of activas) await this.revocar(actor, conexion.id);
    return { revocadas: activas.length };
  }

  /** Solo se pueden reducir permisos; ampliarlos exige volver a autorizar desde el cliente. */
  async reducirPermisos(actor: ActorPanel, conexionId: string, scopes: unknown) {
    const conexion = await this.conexionDeEmpresa(actor, conexionId);
    if (conexion.usuarioId !== actor.id) throw httpError(403, "Solo quien autorizó la integración puede cambiar sus permisos.");
    const nuevos = parsearScopes(Array.isArray(scopes) ? scopes.join(" ") : scopes);
    if (!nuevos.length) throw httpError(400, "Deja al menos un permiso o revoca la integración.");
    if (nuevos.some((s) => !conexion.scopes.includes(s))) {
      throw httpError(400, "Aquí solo puedes quitar permisos; para agregar, vuelve a conectar desde tu asistente de IA.");
    }
    await this.prisma.mcpConexion.update({ where: { id: conexion.id }, data: { scopes: nuevos } });
    await invalidarEstadoMcp({ conexionIds: [conexion.id] });
    await this.auditoria(actor, "MCP_REDUCIR_PERMISOS", conexion.id, `Permisos de ${conexion.clienteNombre}: ${nuevos.join(", ")}.`, {
      antes: conexion.scopes,
      despues: nuevos,
    });
    return { ok: true, permisos: nuevos };
  }

  async actividad(actor: ActorPanel, conexionId: string, limite = 100) {
    await this.conexionDeEmpresa(actor, conexionId);
    const filas = await this.prisma.mcpInvocacion.findMany({
      where: { conexionId, empresaId: actor.empresaId },
      select: {
        id: true,
        herramienta: true,
        nivelRiesgo: true,
        resultado: true,
        codigo: true,
        mensaje: true,
        entidadesAfectadas: true,
        latenciaMs: true,
        creadoEn: true,
      },
      orderBy: { creadoEn: "desc" },
      take: Math.min(Math.max(limite, 1), 200),
    });
    return filas.map((f) => ({ ...f, id: f.id.toString() }));
  }

  async aprobacionesPendientes(actor: ActorPanel) {
    const filas = await this.prisma.mcpConfirmacion.findMany({
      where: {
        usuarioId: actor.id,
        empresaId: actor.empresaId,
        estado: ESTADOS_CONFIRMACION.PENDIENTE_APROBACION,
        expiraEn: { gt: new Date() },
      },
      select: {
        id: true,
        operacion: true,
        resumen: true,
        impacto: true,
        creadaEn: true,
        expiraEn: true,
        conexion: { select: { clienteNombre: true } },
      },
      orderBy: { creadaEn: "desc" },
      take: 50,
    });
    return filas.map((f) => ({
      id: f.id,
      operacion: f.operacion,
      cliente: f.conexion.clienteNombre,
      resumen: f.resumen,
      impacto: f.impacto,
      creadaEn: f.creadaEn,
      expiraEn: f.expiraEn,
    }));
  }

  /**
   * Aprobar no ejecuta: habilita que la IA llame confirmar_operacion durante
   * 15 minutos. Solo el gerente dueno de la conexion decide.
   */
  async decidir(actor: ActorPanel, confirmacionId: string, decision: "aprobar" | "rechazar") {
    const conf = await this.prisma.mcpConfirmacion.findFirst({
      where: { id: confirmacionId, empresaId: actor.empresaId },
      select: { id: true, usuarioId: true, estado: true, expiraEn: true, resumen: true, conexionId: true },
    });
    if (!conf || conf.usuarioId !== actor.id) throw httpError(404, "Aprobación no encontrada.");
    if (conf.estado !== ESTADOS_CONFIRMACION.PENDIENTE_APROBACION || conf.expiraEn.getTime() <= Date.now()) {
      throw httpError(409, "Esta solicitud ya no está pendiente.");
    }
    const aprobar = decision === "aprobar";
    const cambio = await this.prisma.mcpConfirmacion.updateMany({
      where: { id: conf.id, estado: ESTADOS_CONFIRMACION.PENDIENTE_APROBACION },
      data: {
        estado: aprobar ? ESTADOS_CONFIRMACION.APROBADA : ESTADOS_CONFIRMACION.RECHAZADA,
        decididaPorId: actor.id,
        decididaEn: new Date(),
        ...(aprobar ? { expiraEn: new Date(Date.now() + VIGENCIA_TRAS_APROBAR_MS) } : {}),
      },
    });
    if (cambio.count !== 1) throw httpError(409, "Esta solicitud ya no está pendiente.");
    await this.auditoria(
      actor,
      aprobar ? "MCP_APROBAR_OPERACION" : "MCP_RECHAZAR_OPERACION",
      conf.conexionId,
      `${aprobar ? "Aprobó" : "Rechazó"}: ${conf.resumen}`.slice(0, 500),
      { confirmacionId: conf.id },
    );
    return { ok: true, estado: aprobar ? ESTADOS_CONFIRMACION.APROBADA : ESTADOS_CONFIRMACION.RECHAZADA };
  }
}
