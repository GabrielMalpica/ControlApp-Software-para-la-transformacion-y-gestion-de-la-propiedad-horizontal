import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import { EstadoPedidoInterno, Prisma, Rol, type PrismaClient } from "@prisma/client";
import { PermissionService } from "./PermissionService";

const PEDIDO_COMPLETADO_STATES = [
  EstadoPedidoInterno.RECIBIDO,
  EstadoPedidoInterno.ENTREGADO,
] as const;

type HttpError = Error & { status: number };

function makeHttpError(status: number, message: string): HttpError {
  const err = new Error(message) as HttpError;
  err.status = status;
  return err;
}

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

    const { empresaId, permissions } = await this.permissionService.getEffectivePermissionsForUser({
      userId: usuario.id,
      role: normalizedRole,
    });

    return {
      id: usuario.id,
      nombre: usuario.nombre,
      correo: usuario.correo,
      rol: usuario.rol,
      empresaId,
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

  async login(correo: string, contrasena: string) {
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

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) throw makeHttpError(500, "JWT_SECRET no está configurado");

    const sessionUser = await this.buildSessionUser({
      id: usuario.id,
      nombre: usuario.nombre,
      correo: usuario.correo,
      rol: usuario.rol,
      requiereCambioContrasena: usuario.requiereCambioContrasena,
    });

    const token = jwt.sign(
      {
        sub: usuario.id,
        rol: usuario.rol,
        correo: usuario.correo,
        empresaId: sessionUser.empresaId || undefined,
      },
      jwtSecret,
      { expiresIn: "8h" },
    );

    return {
      token,
      user: sessionUser,
    };
  }

  async cambiarContrasena(
    userId: string,
    contrasenaActual: string,
    nuevaContrasena: string
  ) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: { id: true, contrasena: true, activo: true },
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
  }

  async cambiarContrasenaInicial(userId: string, nuevaContrasena: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { id: userId },
      select: {
        id: true,
        contrasena: true,
        activo: true,
        requiereCambioContrasena: true,
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
  }

  async recuperarContrasena(
    correo: string,
    id: string,
    nuevaContrasena: string
  ) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { correo },
      select: { id: true, contrasena: true, activo: true },
    });

    if (!usuario || usuario.id !== id) {
      throw makeHttpError(
        404,
        "No encontramos un usuario con ese correo y cedula"
      );
    }
    if (!usuario.activo) throw makeHttpError(403, "Usuario inactivo");

    const okNuevaIgual = await bcrypt.compare(
      nuevaContrasena,
      usuario.contrasena
    );
    if (okNuevaIgual) {
      throw makeHttpError(
        400,
        "La nueva contrasena debe ser diferente a la anterior"
      );
    }

    const hash = await bcrypt.hash(nuevaContrasena, 10);
    await this.prisma.usuario.update({
      where: { id: usuario.id },
      data: { contrasena: hash },
    });
  }

  async cambiarContrasenaUsuarioPorGerente(
    actorUserId: string,
    targetUserId: string,
    nuevaContrasena: string
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
        select: { id: true, rol: true, activo: true },
      }),
      this.prisma.usuario.findUnique({
        where: { id: targetUserId },
        select: { id: true, contrasena: true, activo: true, nombre: true },
      }),
    ]);

    if (!actor) throw makeHttpError(404, "Usuario solicitante no encontrado");
    if (!actor.activo) throw makeHttpError(403, "Usuario solicitante inactivo");
    if (String(actor.rol).trim().toLowerCase() != "gerente") {
      throw makeHttpError(403, "Solo el gerente puede cambiar contrasenas de otros usuarios");
    }

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");
    if (!usuario.activo) throw makeHttpError(403, "El usuario objetivo esta inactivo");

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

    const hash = await bcrypt.hash(nuevaContrasena, 10);
    await this.prisma.usuario.update({
      where: { id: targetUserId },
      data: { contrasena: hash },
    });

    return { ok: true, nombre: usuario.nombre };
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
              select: { nit: true, nombre: true },
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
