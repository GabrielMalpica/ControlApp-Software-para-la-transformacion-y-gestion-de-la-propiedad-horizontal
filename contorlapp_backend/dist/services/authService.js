"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AuthService = void 0;
const bcrypt_1 = __importDefault(require("bcrypt"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
function makeHttpError(status, message) {
    const err = new Error(message);
    err.status = status;
    return err;
}
class AuthService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async login(correo, contrasena) {
        const credencialesInvalidas = "Credenciales inválidas";
        const usuario = await this.prisma.usuario.findFirst({
            where: {
                correo: {
                    equals: correo.trim(),
                    mode: "insensitive",
                },
            },
        });
        if (!usuario)
            throw makeHttpError(401, credencialesInvalidas);
        const ok = await bcrypt_1.default.compare(contrasena, usuario.contrasena);
        if (!ok)
            throw makeHttpError(401, credencialesInvalidas);
        const jwtSecret = process.env.JWT_SECRET;
        if (!jwtSecret)
            throw makeHttpError(500, "JWT_SECRET no está configurado");
        const token = jsonwebtoken_1.default.sign({ sub: usuario.id, rol: usuario.rol, correo: usuario.correo }, jwtSecret, { expiresIn: "8h" });
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
    async cambiarContrasena(userId, contrasenaActual, nuevaContrasena) {
        const usuario = await this.prisma.usuario.findUnique({
            where: { id: userId },
            select: { id: true, contrasena: true, activo: true },
        });
        if (!usuario)
            throw makeHttpError(404, "Usuario no encontrado");
        if (!usuario.activo)
            throw makeHttpError(403, "Usuario inactivo");
        const okActual = await bcrypt_1.default.compare(contrasenaActual, usuario.contrasena);
        if (!okActual) {
            throw makeHttpError(400, "La contrasena actual no es correcta");
        }
        const okNuevaIgual = await bcrypt_1.default.compare(nuevaContrasena, usuario.contrasena);
        if (okNuevaIgual) {
            throw makeHttpError(400, "La nueva contrasena debe ser diferente a la actual");
        }
        const hash = await bcrypt_1.default.hash(nuevaContrasena, 10);
        await this.prisma.usuario.update({
            where: { id: userId },
            data: { contrasena: hash },
        });
    }
    async recuperarContrasena(correo, id, nuevaContrasena) {
        const usuario = await this.prisma.usuario.findUnique({
            where: { correo },
            select: { id: true, contrasena: true, activo: true },
        });
        if (!usuario || usuario.id !== id) {
            throw makeHttpError(404, "No encontramos un usuario con ese correo y cedula");
        }
        if (!usuario.activo)
            throw makeHttpError(403, "Usuario inactivo");
        const okNuevaIgual = await bcrypt_1.default.compare(nuevaContrasena, usuario.contrasena);
        if (okNuevaIgual) {
            throw makeHttpError(400, "La nueva contrasena debe ser diferente a la anterior");
        }
        const hash = await bcrypt_1.default.hash(nuevaContrasena, 10);
        await this.prisma.usuario.update({
            where: { id: usuario.id },
            data: { contrasena: hash },
        });
    }
    async cambiarContrasenaUsuarioPorGerente(actorUserId, targetUserId, nuevaContrasena) {
        if (actorUserId === targetUserId) {
            throw makeHttpError(400, "Para tu propia cuenta usa la opcion de cambiar contrasena personal");
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
        if (!actor)
            throw makeHttpError(404, "Usuario solicitante no encontrado");
        if (!actor.activo)
            throw makeHttpError(403, "Usuario solicitante inactivo");
        if (String(actor.rol).trim().toLowerCase() != "gerente") {
            throw makeHttpError(403, "Solo el gerente puede cambiar contrasenas de otros usuarios");
        }
        if (!usuario)
            throw makeHttpError(404, "Usuario no encontrado");
        if (!usuario.activo)
            throw makeHttpError(403, "El usuario objetivo esta inactivo");
        const okNuevaIgual = await bcrypt_1.default.compare(nuevaContrasena, usuario.contrasena);
        if (okNuevaIgual) {
            throw makeHttpError(400, "La nueva contrasena debe ser diferente a la actual del usuario");
        }
        const hash = await bcrypt_1.default.hash(nuevaContrasena, 10);
        await this.prisma.usuario.update({
            where: { id: targetUserId },
            data: { contrasena: hash },
        });
        return { ok: true, nombre: usuario.nombre };
    }
}
exports.AuthService = AuthService;
