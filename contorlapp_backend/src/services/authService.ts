import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import type { PrismaClient } from "@prisma/client";

export class AuthService {
  constructor(private prisma: PrismaClient) {}

  async login(correo: string, contrasena: string) {
    const usuario = await this.prisma.usuario.findUnique({ where: { correo } });

    if (!usuario) throw new Error("Usuario no encontrado");

    const ok = await bcrypt.compare(contrasena, usuario.contrasena);
    if (!ok) throw new Error("Contraseña incorrecta");

    const token = jwt.sign(
      { sub: usuario.id, rol: usuario.rol, correo: usuario.correo },
      process.env.JWT_SECRET as string,
      { expiresIn: "8h" }
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
