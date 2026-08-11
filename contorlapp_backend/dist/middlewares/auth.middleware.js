"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authRequiredUnlessPublic = exports.authOptional = exports.authRequired = void 0;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const RedisService_1 = require("../services/RedisService");
function isPublicRequest(method, path) {
    if (method === "GET" && (path === "/" || path === "/ping"))
        return true;
    if (method === "POST" &&
        (path === "/auth/login" || path === "/auth/recuperar-contrasena")) {
        return true;
    }
    return (method === "GET" &&
        (path === "/commerce/catalogo" || path.startsWith("/commerce/catalogo/")));
}
const authRequired = async (req, res, next) => {
    const header = req.headers.authorization;
    if (!header || !header.startsWith("Bearer ")) {
        res.status(401).json({ message: "Token requerido" });
        return;
    }
    const token = header.replace("Bearer ", "").trim();
    try {
        const payload = jsonwebtoken_1.default.verify(token, process.env.JWT_SECRET);
        if (payload.jti && (await (0, RedisService_1.isTokenRevoked)(payload.jti))) {
            res.status(401).json({ message: "Token revocado" });
            return;
        }
        req.user = payload;
        next();
    }
    catch {
        res.status(401).json({ message: "Token inválido o expirado" });
    }
};
exports.authRequired = authRequired;
const authOptional = async (req, _res, next) => {
    if (req.user) {
        next();
        return;
    }
    const header = req.headers.authorization;
    if (!header || !header.startsWith("Bearer ")) {
        next();
        return;
    }
    const token = header.replace("Bearer ", "").trim();
    try {
        const payload = jsonwebtoken_1.default.verify(token, process.env.JWT_SECRET);
        req.user = payload.jti && (await (0, RedisService_1.isTokenRevoked)(payload.jti)) ? undefined : payload;
    }
    catch {
        req.user = undefined;
    }
    next();
};
exports.authOptional = authOptional;
/**
 * Cierre defensivo global. Las rutas siguen declarando autorizacion por rol y
 * permiso; esta allowlist evita que una ruta nueva quede publica por omision.
 */
const authRequiredUnlessPublic = (req, res, next) => {
    if (isPublicRequest(req.method.toUpperCase(), req.path)) {
        next();
        return;
    }
    (0, exports.authRequired)(req, res, next);
};
exports.authRequiredUnlessPublic = authRequiredUnlessPublic;
