import bcrypt from "bcrypt";
import { EstadoPedidoInterno, Prisma, Rol, type PrismaClient } from "@prisma/client";
import type { ActorAuditoria } from "../model/Auditoria";
import { motivoRechazoGestionUsuario } from "../utils/jerarquiaRoles";
import {
  DURACION_TOKEN_APP_SEG,
  duracionTokenWebSeg,
  firmarTokenSesion,
} from "../utils/jwtSesion";
import { AuditoriaService } from "./AuditoriaService";
import { PermissionService } from "./PermissionService";
import {
  cerrarTodasLasSesiones,
  crearSesionRefresh,
  invalidarEstadoSesion,
  rotarSesionRefresh,
  type SesionRefreshEmitida,
} from "./SesionService";

const PEDIDO_COMPLETADO_STATES = [
  EstadoPedidoInterno.RECIBIDO,
  EstadoPedidoInterno.ENTREGADO,
] as const;

type HttpError = Error & { status: number; code?: string };

function makeHttpError(status: number, message: string, code?: string): HttpError {
  const err = new Error(message) as HttpError;
  err.status = status;
  if (code) err.code = code;
  return err;
}

export type OpcionesSesion = {
  /** Web: token corto en memoria + cookie HttpOnly de renovacion. */
  sesionWeb?: boolean;
  userAgent?: string | null;
};

export type SesionEmitida = {
  token: string;
  tokenExpiraEn: Date;
  user: Awaited<ReturnType<AuthService["obtenerSesionUsuario"]>>;
  /** Solo sesion web: el controller lo pone en la cookie y nunca en el cuerpo. */
  refresh?: SesionRefreshEmitida;
};

export const MENSAJE_RECUPERACION_DESACTIVADA =
  "Por seguridad, la contraseña ya no se recupera con correo y cédula. Pide a tu gerente o jefe de operaciones que la restablezca desde ControlApp; al entrar te pedirá crear una nueva.";

export class AuthService {
  private permissionService: PermissionService;

  constructor(private prisma: PrismaClient) {
    this.permissionService = new PermissionService(prisma);
  }

  private normalizeRole(value: string): Rol | null {
    const normalized = value.trim().toLowerCase();
    return Object.values(Rol).find((role) => role === normalized) ?? null;
  }

  private async buildSessionUser(usuario: {
    id: string;
    nombre: string;
    correo: string;
    rol: string;
    requiereCambioContrasena: boolean;
  }) {
    const normalizedRole = this.normalizeRole(usuario.rol);

    if (!normalizedRole) {
      return {
        id: usuario.id,
        nombre: usuario.nombre,
        correo: usuario.correo,
        rol: usuario.rol,
        empresaId: "",
        permissions: [] as string[],
        requiereCambioContrasena: usuario.requiereCambioContrasena,
      };
    }

    let empresaId = "";
    let permissions: string[];
    try {
      const effective = await this.permissionService.getEffectivePermissionsForUser({
        userId: usuario.id,
        role: normalizedRole,
      });
      empresaId = effective.empresaId;
      permissions = effective.permissions;
    } catch (error) {
      if (normalizedRole !== Rol.gerente) throw error;
      permissions = Array.from(PermissionService.defaultPermissionsForRole(Rol.gerente));
    }

    let conjuntoId = "";
    if (normalizedRole === Rol.operario && empresaId) {
      const conjunto = await this.prisma.conjunto.findFirst({
        where: {
          empresaId,
          activo: true,
          operarios: { some: { id: usuario.id } },
        },
        select: { nit: true },
        orderBy: { nit: "asc" },
      });
      conjuntoId = conjunto?.nit ?? "";
    }

    return {
      id: usuario.id,
      nombre: usuario.nombre,
      correo: usuario.correo,
      rol: usuario.rol,
      empresaId,
      conjuntoId,
      permissions,
      requiereCambioContrasena: usuario.requiereCambioContrasena,
    };
  }

  async obtenerSesionUsuario(userId: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: { id: true, nombre: true, correo: true, rol: true, requiereCambioContrasena: true },
    });

    if (!usuario) {
      throw makeHttpError(404, "Usuario no encontrado");
    }

    return this.buildSessionUser(usuario);
  }

  async login(correo: string, contrasena: string, opciones: OpcionesSesion = {}) {
    const usuario = await this.verificarCredenciales(correo, contrasena);
    return this.emitirSesion(usuario.id, opciones);
  }

  /**
   * Correo + contrasena de ControlApp. La usan el login de la app y el del
   * servidor de autorizacion del MCP (misma regla para ambos).
   */
  async verificarCredenciales(
    correo: string,
    contrasena: string,
  ): Promise<{ id: string; nombre: string; rol: string }> {
    const credencialesInvalidas = "Credenciales inválidas";

    const usuario = await this.prisma.usuario.findFirst({
      where: {
        correo: {
          equals: correo.trim(),
          mode: "insensitive",
        },
      },
    });

    if (!usuario) throw makeHttpError(401, credencialesInvalidas);

    const ok = await bcrypt.compare(contrasena, usuario.contrasena);
    if (!ok) throw makeHttpError(401, credencialesInvalidas);

    // Despues de validar la contrasena: un tercero sin ella no puede saber si
    // la cuenta existe o esta inactiva.
    if (!usuario.activo) {
      throw makeHttpError(403, "Tu usuario está inactivo. Comunícate con tu gerente.");
    }

    return { id: usuario.id, nombre: usuario.nombre, rol: usuario.rol };
  }

  /**
   * Emite una sesion para un usuario ya autenticado: JWT (8 h en la app, corto
   * en web) y, en web, un token de renovacion para la cookie HttpOnly.
   */
  async emitirSesion(usuarioId: string, opciones: OpcionesSesion = {}): Promise<SesionEmitida> {
    const usuario = await this.usuarioParaSesion(usuarioId);
    const user = await this.buildSessionUser(usuario);
    const refresh = opciones.sesionWeb
      ? await crearSesionRefresh(this.prisma, {
          usuarioId: usuario.id,
          versionSesion: usuario.versionSesion,
          userAgent: opciones.userAgent,
        })
      : undefined;

    return { ...this.firmarSesion(usuario, user.empresaId, opciones.sesionWeb === true), user, refresh };
  }

  /** Renueva la sesion web con el token de la cookie (que tambien rota). */
  async refrescarSesionWeb(tokenRefresh: string, userAgent?: string | null): Promise<SesionEmitida> {
    const rotado = await rotarSesionRefresh(this.prisma, tokenRefresh, userAgent);
    const usuario = await this.usuarioParaSesion(rotado.usuarioId);
    const user = await this.buildSessionUser(usuario);
    return {
      ...this.firmarSesion(usuario, user.empresaId, true),
      user,
      refresh: { token: rotado.token, expiraEn: rotado.expiraEn },
    };
  }

  private async usuarioParaSesion(usuarioId: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: usuarioId },
      select: {
        id: true,
        nombre: true,
        correo: true,
        rol: true,
        activo: true,
        requiereCambioContrasena: true,
        versionSesion: true,
      },
    });
    if (!usuario || !usuario.activo) {
      throw makeHttpError(401, "Tu sesión expiró. Inicia sesión de nuevo.", "SESION_INVALIDA");
    }
    return usuario;
  }

  private firmarSesion(
    usuario: { id: string; rol: string; correo: string; versionSesion: number },
    empresaId: string,
    sesionWeb: boolean,
  ) {
    const firmado = firmarTokenSesion(
      {
        usuarioId: usuario.id,
        rol: usuario.rol,
        correo: usuario.correo,
        empresaId,
        versionSesion: usuario.versionSesion,
      },
      sesionWeb ? duracionTokenWebSeg() : DURACION_TOKEN_APP_SEG,
    );
    return { token: firmado.token, tokenExpiraEn: firmado.expiraEn };
  }

  /** Cierra todas las sesiones del usuario (todos sus dispositivos). */
  async cerrarTodasLasSesiones(usuarioId: string): Promise<void> {
    await cerrarTodasLasSesiones(this.prisma, usuarioId, "CIERRE_POR_USUARIO");
  }

  async cambiarContrasena(
    userId: string,
    contrasenaActual: string,
    nuevaContrasena: string,
    opciones: OpcionesSesion = {},
  ): Promise<SesionEmitida> {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: { id: true, contrasena: true, activo: true, rol: true, nombre: true },
    });

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");
    if (!usuario.activo) throw makeHttpError(403, "Usuario inactivo");

    const okActual = await bcrypt.compare(contrasenaActual, usuario.contrasena);
    if (!okActual) {
      throw makeHttpError(400, "La contrasena actual no es correcta");
    }

    const okNuevaIgual = await bcrypt.compare(
      nuevaContrasena,
      usuario.contrasena
    );
    if (okNuevaIgual) {
      throw makeHttpError(
        400,
        "La nueva contrasena debe ser diferente a la actual"
      );
    }

    const hash = await bcrypt.hash(nuevaContrasena, 10);
    await this.prisma.usuario.update({
      where: { id: userId },
      data: {
        contrasena: hash,
        requiereCambioContrasena: false,
      },
    });

    return this.renovarTrasCambioDeContrasena(usuario, "CAMBIAR_CONTRASENA", opciones);
  }

  async cambiarContrasenaInicial(
    userId: string,
    nuevaContrasena: string,
    opciones: OpcionesSesion = {},
  ): Promise<SesionEmitida> {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        contrasena: true,
        activo: true,
        requiereCambioContrasena: true,
        rol: true,
        nombre: true,
      },
    });

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");
    if (!usuario.activo) throw makeHttpError(403, "Usuario inactivo");
    if (!usuario.requiereCambioContrasena) {
      throw makeHttpError(403, "Tu cuenta no requiere cambio inicial de contrasena");
    }

    const okNuevaIgual = await bcrypt.compare(nuevaContrasena, usuario.contrasena);
    if (okNuevaIgual) {
      throw makeHttpError(
        400,
        "La nueva contrasena debe ser diferente a la temporal"
      );
    }

    const hash = await bcrypt.hash(nuevaContrasena, 10);
    await this.prisma.usuario.update({
      where: { id: userId },
      data: {
        contrasena: hash,
        requiereCambioContrasena: false,
      },
    });

    return this.renovarTrasCambioDeContrasena(usuario, "CAMBIAR_CONTRASENA_INICIAL", opciones);
  }

  /**
   * Tras cambiar la propia contrasena se cierran las sesiones de todos los
   * dispositivos (alguien pudo conocer la anterior) y este recibe una nueva,
   * para no obligar a volver a iniciar sesion aqui.
   */
  private async renovarTrasCambioDeContrasena(
    usuario: { id: string; rol: string; nombre: string },
    accion: string,
    opciones: OpcionesSesion,
  ): Promise<SesionEmitida> {
    await cerrarTodasLasSesiones(this.prisma, usuario.id, accion);
    await this.auditarSeguridad({
      usuarioId: usuario.id,
      accion,
      actor: { id: usuario.id, rol: usuario.rol, nombre: usuario.nombre },
      descripcion: "El usuario cambió su contraseña; se cerraron sus otras sesiones.",
    });
    return this.emitirSesion(usuario.id, opciones);
  }

  async cambiarContrasenaUsuarioPorGerente(
    actorUserId: string,
    targetUserId: string,
    nuevaContrasena: string,
    empresaId?: string | null,
  ) {
    if (actorUserId === targetUserId) {
      throw makeHttpError(
        400,
        "Para tu propia cuenta usa la opcion de cambiar contrasena personal"
      );
    }

    const [actor, usuario] = await Promise.all([
      this.prisma.usuario.findUnique({
        where: { id: actorUserId },
        select: { id: true, activo: true, rol: true, nombre: true },
      }),
      this.prisma.usuario.findUnique({
        where: { id: targetUserId },
        select: { id: true, contrasena: true, activo: true, nombre: true, rol: true },
      }),
    ]);

    if (!actor) throw makeHttpError(404, "Usuario solicitante no encontrado");
    if (!actor.activo) throw makeHttpError(403, "Usuario solicitante inactivo");
    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");
    if (!usuario.activo) throw makeHttpError(403, "El usuario objetivo esta inactivo");

    // Misma jerarquia que la gestion de usuarios (GerenteServices): un gerente
    // restablece la de cualquiera, incluido otro gerente para recuperar su
    // acceso; los demas solo la de roles estrictamente inferiores al suyo.
    const rechazo = motivoRechazoGestionUsuario({
      actor: { id: actor.id, rol: actor.rol },
      objetivoId: usuario.id,
      rolActual: usuario.rol,
    });
    if (rechazo) throw makeHttpError(403, rechazo);

    const okNuevaIgual = await bcrypt.compare(
      nuevaContrasena,
      usuario.contrasena
    );
    if (okNuevaIgual) {
      throw makeHttpError(
        400,
        "La nueva contrasena debe ser diferente a la actual del usuario"
      );
    }

    // Queda como temporal: el usuario debe cambiarla al entrar (el backend no
    // le deja hacer nada mas) y todas sus sesiones abiertas se cierran.
    const hash = await bcrypt.hash(nuevaContrasena, 10);
    await this.prisma.usuario.update({
      where: { id: targetUserId },
      data: { contrasena: hash, requiereCambioContrasena: true },
    });
    await cerrarTodasLasSesiones(this.prisma, targetUserId, "CONTRASENA_RESTABLECIDA");
    await this.auditarSeguridad({
      usuarioId: targetUserId,
      empresaId,
      accion: "RESTABLECER_CONTRASENA",
      actor: { id: actor.id, rol: actor.rol, nombre: actor.nombre },
      descripcion: `${actor.nombre} restableció la contraseña de ${usuario.nombre} (${usuario.rol}); se cerraron sus sesiones y deberá crear una nueva al entrar.`,
    });

    return { ok: true, nombre: usuario.nombre };
  }

  private async auditarSeguridad(evento: {
    usuarioId: string;
    accion: string;
    actor: ActorAuditoria;
    descripcion: string;
    empresaId?: string | null;
  }): Promise<void> {
    await invalidarEstadoSesion(evento.usuarioId);
    await new AuditoriaService(this.prisma).registrar({
      modulo: "SEGURIDAD",
      entidad: "Usuario",
      entidadId: evento.usuarioId,
      accion: evento.accion,
      empresaId: evento.empresaId ?? null,
      actor: evento.actor,
      descripcion: evento.descripcion,
    });
  }

  async obtenerResumenPerfil(userId: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        nombre: true,
        correo: true,
        rol: true,
        activo: true,
        requiereCambioContrasena: true,
        administrador: {
          select: {
            conjuntos: {
              select: { nit: true, nombre: true },
              orderBy: { nombre: "asc" },
            },
          },
        },
        gerente: {
          select: {
            empresa: {
              select: {
                conjuntos: {
                  select: { nit: true, nombre: true },
                  orderBy: { nombre: "asc" },
                },
              },
            },
          },
        },
        jefeOperaciones: {
          select: {
            empresa: {
              select: {
                conjuntos: {
                  select: { nit: true, nombre: true },
                  orderBy: { nombre: "asc" },
                },
              },
            },
          },
        },
        residente: {
          select: {
            tipoUnidad: true,
            sector: true,
            unidad: true,
            conjunto: {
              // direccion: para prellenar "dirección de entrega" en el
              // checkout del residente con la del conjunto (ver
              // resident_cart_page.dart), igual que ya se hace en el
              // checkout de conjunto con conjunto.direccion.
              select: { nit: true, nombre: true, direccion: true },
            },
          },
        },
        // El operario está vinculado a sus conjuntos (normalmente uno): el
        // panel necesita el nombre, no solo el NIT.
        operario: {
          select: {
            conjuntos: {
              select: { nit: true, nombre: true },
              orderBy: { nombre: "asc" },
            },
          },
        },
      },
    });

    if (!usuario) {
      throw makeHttpError(404, "Usuario no encontrado");
    }

    const [pedidoStats, puntosStats] = await Promise.all([
      this.prisma.pedidoApp.aggregate({
        where: { usuarioId: userId },
        _count: { _all: true },
        _sum: { total: true },
      }),
      this.prisma.movimientoPuntos.aggregate({
        where: { usuarioId: userId },
        _sum: { puntos: true },
      }),
    ]);

    const pedidosCompletados = await this.prisma.pedidoApp.count({
      where: {
        usuarioId: userId,
        estado: { in: [...PEDIDO_COMPLETADO_STATES] },
      },
    });

    const comprasCompletadas = await this.prisma.pedidoApp.aggregate({
      where: {
        usuarioId: userId,
        estado: { in: [...PEDIDO_COMPLETADO_STATES] },
      },
      _sum: { total: true },
    });

    const conjuntos = usuario.administrador?.conjuntos?.map((item) => ({
      nit: item.nit,
      nombre: item.nombre,
    })) ?? [];

    const conjuntosEmpresa =
      usuario.gerente?.empresa?.conjuntos ??
      usuario.jefeOperaciones?.empresa?.conjuntos ??
      [];
    for (const item of conjuntosEmpresa) {
      if (!conjuntos.some((conjunto) => conjunto.nit === item.nit)) {
        conjuntos.push({ nit: item.nit, nombre: item.nombre });
      }
    }

    for (const item of usuario.operario?.conjuntos ?? []) {
      if (!conjuntos.some((conjunto) => conjunto.nit === item.nit)) {
        conjuntos.push({ nit: item.nit, nombre: item.nombre });
      }
    }

    if (usuario.residente?.conjunto) {
      conjuntos.push({
        nit: usuario.residente.conjunto.nit,
        nombre: usuario.residente.conjunto.nombre,
      });
    }

    let beneficiosActivos = 0;
    if (conjuntos.length) {
      try {
        beneficiosActivos = await this.prisma.beneficioPuntos.count({
          where: {
            activo: true,
            config: {
              activo: true,
              conjuntoId: { in: conjuntos.map((conjunto) => conjunto.nit) },
            },
          },
        });
      } catch (error) {
        // Mantiene operativo el perfil durante el despliegue previo de la migracion 8-10.
        if (
          !(error instanceof Prisma.PrismaClientKnownRequestError) ||
          error.code !== "P2021"
        ) {
          throw error;
        }
      }
    }

    return {
      user: {
        id: usuario.id,
        nombre: usuario.nombre,
        correo: usuario.correo,
        rol: usuario.rol,
        activo: usuario.activo,
        requiereCambioContrasena: usuario.requiereCambioContrasena,
      },
      residente: usuario.residente
        ? {
            tipoUnidad: usuario.residente.tipoUnidad,
            sector: usuario.residente.sector,
            unidad: usuario.residente.unidad,
            conjunto: usuario.residente.conjunto,
          }
        : null,
      conjuntos,
      metricas: {
        totalPedidos: pedidoStats._count._all,
        pedidosCompletados,
        totalCompras: Number(pedidoStats._sum.total ?? 0),
        comprasCompletadas: Number(comprasCompletadas._sum.total ?? 0),
        puntos: puntosStats._sum.puntos ?? 0,
        beneficiosActivos,
      },
    };
  }
}
