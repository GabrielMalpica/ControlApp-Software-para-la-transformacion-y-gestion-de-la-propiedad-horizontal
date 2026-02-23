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
}
