"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.requireRoles = requireRoles;
function requireRoles(...roles) {
    return (req, res, next) => {
        const rol = req.user?.rol;
        if (!rol) {
            res.status(401).json({ message: "No autenticado" });
            return;
        }
        if (!roles.includes(rol)) {
            res.status(403).json({ message: "No autorizado para este recurso" });
            return;
        }
        next();
    };
}
