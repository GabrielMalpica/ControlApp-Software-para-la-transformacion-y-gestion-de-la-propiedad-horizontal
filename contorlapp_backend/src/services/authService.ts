import { PrismaClient } from '../generated/prisma';
import bcrypt from "bcrypt";

export class AuthService {
  constructor(private prisma: PrismaClient) {}

  async login(correo: string, contrasena: string) {
    const usuario = await this.prisma.usuario.findUnique({
      where: { correo },
    });

    if (!usuario) {
      throw new Error("❌ Usuario no encontrado.");
    }

    const passwordValida = await bcrypt.compare(contrasena, usuario.contrasena);

    if (!passwordValida) {
      throw new Error("❌ Contraseña incorrecta.");
    }

    return {
      id: usuario.id,
      nombre: usuario.nombre,
      correo: usuario.correo,
      rol: usuario.rol,
    };
  }
}
