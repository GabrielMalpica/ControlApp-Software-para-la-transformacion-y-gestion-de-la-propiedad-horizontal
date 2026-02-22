// src/controllers/AuthController.ts
import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { AuthService } from "../services/authService";

const LoginSchema = z.object({
  correo: z.string().email(),
  contrasena: z.string().min(1),
});

const CambiarContrasenaSchema = z.object({
  contrasenaActual: z.string().min(1),
  nuevaContrasena: z.string().min(8),
});

const RecuperarContrasenaSchema = z.object({
  correo: z.string().email(),
  id: z.string().min(5),
  nuevaContrasena: z.string().min(8),
});

const service = new AuthService(prisma);

export class AuthController {
  // POST /auth/login
  login: RequestHandler = async (req, res, next) => {
    try {
      const { correo, contrasena } = LoginSchema.parse(req.body);

      const result = await service.login(correo.trim().toLowerCase(), contrasena);

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

  // POST /auth/cambiar-contrasena
  cambiarContrasena: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { contrasenaActual, nuevaContrasena } =
        CambiarContrasenaSchema.parse(req.body);

      await service.cambiarContrasena(userId, contrasenaActual, nuevaContrasena);

      res.json({ ok: true, message: "Contrasena actualizada correctamente" });
    } catch (err) {
      next(err);
    }
  };

  // POST /auth/recuperar-contrasena
  recuperarContrasena: RequestHandler = async (req, res, next) => {
    try {
      const { correo, id, nuevaContrasena } = RecuperarContrasenaSchema.parse(
        req.body
      );

      await service.recuperarContrasena(
        correo.trim().toLowerCase(),
        id.trim(),
        nuevaContrasena
      );

      res.json({ ok: true, message: "Contrasena restablecida correctamente" });
    } catch (err) {
      next(err);
    }
  };
}
