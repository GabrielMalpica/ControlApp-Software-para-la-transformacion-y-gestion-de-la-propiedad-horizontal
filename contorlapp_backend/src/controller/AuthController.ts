// src/controllers/AuthController.ts
import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { AuthService } from "../services/authService";

const LoginSchema = z.object({
  correo: z.string().email(),
  contrasena: z.string().min(1),
});

const service = new AuthService(prisma);

export class AuthController {

  // POST /auth/login
  login: RequestHandler = async (req, res, next) => {
    try {
      const { correo, contrasena } = LoginSchema.parse(req.body);

      const result = await service.login(correo, contrasena);

      res.json(result);
    } catch (err) {
      next(err);
    }
  };

  // GET /auth/me
  me: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const usuario = await prisma.usuario.findUnique({
        where: { id: userId },
        select: { id: true, nombre: true, correo: true, rol: true },
      });

      if (!usuario) {
        res.status(404).json({ message: "Usuario no existe" });
        return;
      }

      res.json({ user: usuario });
    } catch (err) {
      next(err);
    }
  };
}
