"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
require("dotenv/config");
process.env.TZ = process.env.TZ || "America/Bogota";
const express_1 = __importDefault(require("express"));
const cors_1 = __importDefault(require("cors"));
const client_1 = require("@prisma/client");
const zod_1 = require("zod");
const Rutas_1 = __importDefault(require("./routes/Rutas"));
const prisma_1 = require("./db/prisma");
const NotificacionService_1 = require("./services/NotificacionService");
if (!process.env.JWT_SECRET) {
    throw new Error("Falta JWT_SECRET en el archivo .env");
}
const app = (0, express_1.default)();
const corsOptions = {
    origin: true,
    credentials: true,
    methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "x-empresa-id"],
};
app.use((0, cors_1.default)(corsOptions));
app.options(/.*/, (0, cors_1.default)(corsOptions));
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
function fixMojibake(text) {
    const replacements = [
        ["á", "a"],
        ["é", "e"],
        ["í", "i"],
        ["ó", "o"],
        ["ú", "u"],
        ["ñ", "n"],
        ["ü", "u"],
        ["¿", ""],
        ["¡", ""],
        ["✅", ""],
        ["❌", ""],
        ["⚠", ""],
        ["…", "..."],
        ["–", "-"],
        ["—", "-"],
        ["“", '"'],
        ["”", '"'],
        ["‘", "'"],
        ["’", "'"],
    ];
    let out = text;
    for (const [from, to] of replacements) {
        out = out.split(from).join(to);
    }
    return out.replace(/\s+/g, " ").trim();
}
function normalizeBusinessMessage(rawMessage) {
    const clean = fixMojibake(rawMessage);
    if (!clean)
        return { message: "" };
    if (/^MAQUINARIA_OCUPADA_\d+$/i.test(clean)) {
        return {
            code: clean.toUpperCase(),
            message: "La maquinaria seleccionada ya esta ocupada en ese horario.",
        };
    }
    switch (clean.toUpperCase()) {
        case "EMAIL_YA_REGISTRADO":
            return {
                code: "EMAIL_YA_REGISTRADO",
                message: "Ya existe un usuario con ese correo.",
            };
        case "NO_ES_CORRECTIVA":
            return {
                code: "NO_ES_CORRECTIVA",
                message: "Solo aplica para tareas correctivas.",
            };
        case "MOTIVO_REQUERIDO":
            return {
                code: "MOTIVO_REQUERIDO",
                message: "Debes indicar un motivo para continuar.",
            };
        case "ACCION_REEMPLAZO_REQUERIDA":
            return {
                code: "ACCION_REEMPLAZO_REQUERIDA",
                message: "Debes elegir como reemplazar las tareas afectadas.",
            };
        case "REEMPLAZO_NO_VALIDO":
            return {
                code: "REEMPLAZO_NO_VALIDO",
                message: "La seleccion no permite realizar ese reemplazo.",
            };
        case "REEMPLAZO_SOLO_PREVENTIVA":
            return {
                code: "REEMPLAZO_SOLO_PREVENTIVA",
                message: "Solo se pueden reemplazar tareas preventivas.",
            };
        default:
            return { message: clean };
    }
}
function inferStatusFromMessage(message) {
    const normalized = message.toLowerCase();
    if (normalized.includes("no autenticado") ||
        normalized.includes("token requerido") ||
        normalized.includes("token invalido") ||
        normalized.includes("token expirado")) {
        return 401;
    }
    if (normalized.includes("no autorizado")) {
        return 403;
    }
    if (normalized.includes("no encontrado") ||
        normalized.includes("no existe") ||
        normalized.includes("no registrada") ||
        normalized.includes("no registrado")) {
        return 404;
    }
    if (normalized.includes("ya existe") ||
        normalized.includes("ya esta registrado") ||
        normalized.includes("ya se encuentra registrado")) {
        return 409;
    }
    return 400;
}
function isSafeBusinessMessage(message) {
    const clean = message.trim();
    if (!clean)
        return false;
    const technicalPatterns = [
        /cannot\s+(read|set|convert|destructure)/i,
        /\bundefined\b/i,
        /\bnull\b/i,
        /\bprisma\b/i,
        /\bTypeError\b/i,
        /\bReferenceError\b/i,
        /\bSyntaxError\b/i,
        /\bRangeError\b/i,
        /\bENOENT\b/i,
        /\bECONN/i,
        /\bETIMEDOUT\b/i,
        /\bEADDR/i,
        /\bJWT_SECRET\b/i,
        /unexpected token/i,
        /\s+at\s+.+\(.+\)/i,
    ];
    return !technicalPatterns.some((pattern) => pattern.test(clean));
}
function sendError(res, status, message, extra = {}) {
    const payload = {
        ok: false,
        message,
        error: message,
        ...(extra.code ? { code: extra.code } : {}),
        ...(extra.details != null ? { details: extra.details } : {}),
    };
    res.status(status).json(payload);
}
/* ----------------------- middleware de error (tipado) --------------------- */
const errorHandler = (err, _req, res, _next) => {
    console.error("Error:", err);
    if (err instanceof zod_1.ZodError || err?.name === "ZodError") {
        const issues = Array.isArray(err?.issues)
            ? err.issues
            : Array.isArray(err?.errors)
                ? err.errors
                : [];
        const details = issues.map((issue) => ({
            field: Array.isArray(issue?.path) && issue.path.length > 0
                ? issue.path.join(".")
                : undefined,
            message: fixMojibake(String(issue?.message ?? "Valor invalido.")),
        }));
        const primaryMessage = details.length === 1
            ? details[0].message
            : "Revisa la informacion ingresada.";
        sendError(res, 400, primaryMessage, {
            code: "VALIDATION_ERROR",
            details,
        });
        return;
    }
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError &&
        err.code === "P2002") {
        const target = Array.isArray(err.meta?.target)
            ? err.meta.target.join(",")
            : String(err.meta?.target ?? "");
        if (target.includes("Conjunto") || target.includes("nit")) {
            sendError(res, 409, "Ya existe un conjunto con ese NIT.", {
                code: err.code,
            });
            return;
        }
        sendError(res, 409, "El registro ya existe y debe ser unico.", {
            code: err.code,
        });
        return;
    }
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError &&
        err.code === "P2003") {
        const constraint = String(err.meta?.constraint ?? "");
        if (constraint.includes("Tarea_ubicacionId_fkey")) {
            sendError(res, 400, "No se pudo actualizar el conjunto porque hay tareas asociadas a ubicaciones existentes. Evita eliminar ubicaciones con tareas historicas.", { code: err.code });
            return;
        }
        sendError(res, 400, "No se pudo completar la operacion porque existen datos relacionados que lo impiden.", { code: err.code });
        return;
    }
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError &&
        err.code === "P2025") {
        const cause = String(err.meta?.cause ?? "").toLowerCase();
        if (cause.includes("supervisor")) {
            sendError(res, 400, "No se pudo completar la operacion porque el supervisor seleccionado no existe. Actualiza la lista e intentalo nuevamente.", { code: err.code });
            return;
        }
        sendError(res, 400, "No se pudo completar la operacion porque faltan datos relacionados o ya no existen.", { code: err.code });
        return;
    }
    if (err instanceof client_1.Prisma.PrismaClientKnownRequestError) {
        sendError(res, 500, "Ocurrio un error tecnico al procesar la solicitud. Si el problema continua, por favor contacta al area de TI.", { code: err.code });
        return;
    }
    const rawStatus = typeof err?.status === "number" ? err.status : undefined;
    const normalized = normalizeBusinessMessage(String(err?.message ?? ""));
    if (rawStatus != null) {
        if (rawStatus >= 500 && !isSafeBusinessMessage(normalized.message)) {
            sendError(res, rawStatus, "Ocurrio un error inesperado. Si el problema continua, por favor contacta al area de TI.");
            return;
        }
        sendError(res, rawStatus, normalized.message || "No se pudo completar la solicitud.", { code: normalized.code });
        return;
    }
    if (normalized.message && isSafeBusinessMessage(normalized.message)) {
        sendError(res, inferStatusFromMessage(normalized.message), normalized.message, { code: normalized.code });
        return;
    }
    sendError(res, 500, "Ocurrio un error inesperado. Si el problema continua, por favor contacta al area de TI.");
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
