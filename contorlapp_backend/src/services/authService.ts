import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import type { PrismaClient } from "@prisma/client";

type HttpError = Error & { status: number };

function makeHttpError(status: number, message: string): HttpError {
  const err = new Error(message) as HttpError;
  err.status = status;
  return err;
}

export class AuthService {
  constructor(private prisma: PrismaClient) {}

  async login(correo: string, contrasena: string) {
    const usuario = await this.prisma.usuario.findFirst({
      where: {
        correo: {
          equals: correo.trim(),
          mode: "insensitive",
        },
      },
    });

    if (!usuario) throw makeHttpError(404, "Usuario no encontrado");

    const ok = await bcrypt.compare(contrasena, usuario.contrasena);
    if (!ok) throw makeHttpError(401, "Contraseña incorrecta");

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) throw makeHttpError(500, "JWT_SECRET no está configurado");

    const token = jwt.sign(
      { sub: usuario.id, rol: usuario.rol, correo: usuario.correo },
      jwtSecret,
      { expiresIn: "8h" },
    );

    return {
      token,
      user: {
        id: usuario.id,
        nombre: usuario.nombre,
        correo: usuario.correo,
        rol: usuario.rol,
      },
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
      data: { contrasena: hash },
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
}
