"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthController = void 0;
const prisma_1 = require("../db/prisma");
const zod_1 = require("zod");
const authService_1 = require("../services/authService");
const LoginSchema = zod_1.z.object({
    correo: zod_1.z.string().email(),
    contrasena: zod_1.z.string().min(1),
});
const CambiarContrasenaSchema = zod_1.z.object({
    contrasenaActual: zod_1.z.string().min(1),
    nuevaContrasena: zod_1.z.string().min(8),
});
const RecuperarContrasenaSchema = zod_1.z.object({
    correo: zod_1.z.string().email(),
    id: zod_1.z.string().min(5),
    nuevaContrasena: zod_1.z.string().min(8),
});
const service = new authService_1.AuthService(prisma_1.prisma);
class AuthController {
    constructor() {
        // POST /auth/login
        this.login = async (req, res, next) => {
            try {
                const { correo, contrasena } = LoginSchema.parse(req.body);
                const result = await service.login(correo.trim().toLowerCase(), contrasena);
                res.json(result);
            }
            catch (err) {
                next(err);
            }
        };
        // GET /auth/me
        this.me = async (req, res, next) => {
            try {
                const userId = req.user?.sub;
                if (!userId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const usuario = await prisma_1.prisma.usuario.findUnique({
                    where: { id: userId },
                    select: { id: true, nombre: true, correo: true, rol: true },
                });
                if (!usuario) {
                    res.status(404).json({ message: "Usuario no existe" });
                    return;
                }
                res.json({ user: usuario });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /auth/cambiar-contrasena
        this.cambiarContrasena = async (req, res, next) => {
            try {
                const userId = req.user?.sub;
                if (!userId) {
                    res.status(401).json({ message: "No autenticado" });
                    return;
                }
                const { contrasenaActual, nuevaContrasena } = CambiarContrasenaSchema.parse(req.body);
                await service.cambiarContrasena(userId, contrasenaActual, nuevaContrasena);
                res.json({ ok: true, message: "Contrasena actualizada correctamente" });
            }
            catch (err) {
                next(err);
            }
        };
        // POST /auth/recuperar-contrasena
        this.recuperarContrasena = async (req, res, next) => {
            try {
                const { correo, id, nuevaContrasena } = RecuperarContrasenaSchema.parse(req.body);
                await service.recuperarContrasena(correo.trim().toLowerCase(), id.trim(), nuevaContrasena);
                res.json({ ok: true, message: "Contrasena restablecida correctamente" });
            }
            catch (err) {
                next(err);
            }
        };
    }
}
exports.AuthController = AuthController;
