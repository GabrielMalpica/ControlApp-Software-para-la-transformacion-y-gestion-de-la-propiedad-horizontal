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
}
