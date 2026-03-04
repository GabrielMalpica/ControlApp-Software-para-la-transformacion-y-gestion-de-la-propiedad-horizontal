"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
// src/index.ts
require("dotenv/config");
process.env.TZ = process.env.TZ || "America/Bogota";
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const client_1 = require("@prisma/client");
const Rutas_1 = __importDefault(require("./routes/Rutas"));
const prisma_1 = require("./db/prisma");
const NotificacionService_1 = require("./services/NotificacionService");
if (!process.env.JWT_SECRET) {
    throw new Error("Falta JWT_SECRET en el archivo .env");
}
const app = (0, express_1.default)();
app.use((0, cors_1.default)());
app.use(express_1.default.json());
app.set("json replacer", (_k, v) => typeof v === "bigint" ? v.toString() : v);
/* --------------------------------- health -------------------------------- */
app.get("/", (_req, res) => {
    res.send("API viva");
});
app.get("/ping", async (_req, res, next) => {
    try {
        const count = await prisma_1.prisma.empresa.count();
        res.json({ ok: true, empresaPublicSelect: count });
    }
    catch (e) {
        next(e);
    }
});
/* -------------------------------- rutas ---------------------------------- */
app.use(Rutas_1.default);
/* ----------------------- middleware de error (tipado) --------------------- */
const errorHandler = (err, _req, res, _next) => {
    console.error("Error:", err);
    // Zod
    if (err?.name === "ZodError") {
        res.status(400).json({ error: err.issues ?? err.errors });
        return;
    }
    // Prisma unique constraint
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
        const target = Array.isArray(err.meta?.target)
            ? err.meta.target.join(",")
            : String(err.meta?.target ?? "");
        if (target.includes("Conjunto") || target.includes("nit")) {
            res.status(409).json({ error: "Ya existe un conjunto con ese NIT." });
            return;
        }
        res.status(409).json({ error: "El registro ya existe y debe ser único." });
        return;
    }
    // Prisma foreign key constraint
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError && err.code === "P2003") {
        const constraint = String(err.meta?.constraint ?? "");
        if (constraint.includes("Tarea_ubicacionId_fkey")) {
            res.status(400).json({
                error: "No se pudo actualizar el conjunto porque hay tareas asociadas a ubicaciones existentes. Evita eliminar ubicaciones con tareas históricas.",
            });
            return;
        }
        res.status(400).json({
            error: "No se pudo completar la operación porque existen datos relacionados que lo impiden.",
        });
        return;
    }
    // Prisma registro relacionado/no encontrado
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError && err.code === "P2025") {
        const cause = String(err.meta?.cause ?? "").toLowerCase();
        if (cause.includes("supervisor")) {
            res.status(400).json({
                error: "No se pudo completar la operación porque el supervisor seleccionado no existe. Actualiza la lista e inténtalo nuevamente.",
            });
            return;
        }
        res.status(400).json({
            error: "No se pudo completar la operación porque faltan datos relacionados o ya no existen.",
        });
        return;
    }
    // Otros errores Prisma: no exponer detalles técnicos
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError) {
        res.status(500).json({
            error: "Ocurrió un error técnico al procesar la solicitud. Si el problema continúa, por favor contacta al área de TI.",
        });
        return;
    }
    // Si en tu codigo lanzas e.status, respetalo
    const status = typeof err?.status === "number" ? err.status : 500;
    if (status >= 500) {
        res.status(status).json({
            error: "Ocurrió un error inesperado. Si el problema continúa, por favor contacta al área de TI.",
        });
        return;
    }
    res.status(status).json({ error: err?.message ?? "No se pudo completar la solicitud." });
};
app.use(errorHandler);
/* ------------------------------- levantar server -------------------------- */
const PORT = 3000;
(async () => {
    try {
        await (0, NotificacionService_1.bootstrapNotificacionesSchema)(prisma_1.prisma);
        console.log("Notificaciones inicializadas");
    }
    catch (e) {
        console.error("No se pudo inicializar tabla de notificaciones:", e);
    }
    app.listen(PORT, () => {
        console.log(`API escuchando en http://localhost:${PORT}`);
    });
})();
/* -------------------------- cierre elegante Prisma ------------------------ */
process.on("SIGINT", async () => {
    await prisma_1.prisma.$disconnect();
    process.exit(0);
});
process.on("SIGTERM", async () => {
    await prisma_1.prisma.$disconnect();
    process.exit(0);
});
