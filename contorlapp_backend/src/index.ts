import "dotenv/config";

process.env.TZ = process.env.TZ || "America/Bogota";
import { createHash } from "crypto";
import express, {
  Request,
  Response,
  NextFunction,
  ErrorRequestHandler,
} from "express";
import cors from "cors";
import helmet from "helmet";
import compression from "compression";
import { rateLimit } from "express-rate-limit";
import { Prisma } from "@prisma/client";
import { ZodError } from "zod";
import { mensajeValidacionAmigable } from "./utils/errorFormat";
import rutas from "./routes/Rutas";
import { prisma } from "./db/prisma";
import { bootstrapNotificacionesSchema } from "./services/NotificacionService";
import { authRequiredUnlessPublic } from "./middlewares/auth.middleware";
import { distributedRateLimit } from "./middlewares/rate-limit.middleware";

if (!process.env.JWT_SECRET) {
  throw new Error("Falta JWT_SECRET en el archivo .env");
}

const app = express();
app.set("trust proxy", 1);
const rateLimitDigest = (...parts: string[]) =>
  createHash("sha256").update(parts.join("\u0000")).digest("hex");
const configuredOrigins = [
  ...(process.env.CORS_ALLOWED_ORIGINS ?? "").split(","),
  process.env.FRONTEND_WEB_URL ?? "",
]
  .map((origin) => origin.trim())
  .filter(Boolean)
  .map((origin) => {
    try {
      return new URL(origin).origin;
    } catch {
      return "";
    }
  })
  .filter(Boolean);
const allowedOrigins = new Set(configuredOrigins);
const isDevLocalOrigin = (origin: string) => {
  if (process.env.NODE_ENV === "production") return false;
  try {
    const url = new URL(origin);
    return (
      ["http:", "https:"].includes(url.protocol) &&
      ["localhost", "127.0.0.1", "::1"].includes(url.hostname)
    );
  } catch {
    return false;
  }
};
const corsOptions = {
  origin: (origin: string | undefined, callback: (error: Error | null, allow?: boolean) => void) => {
    if (!origin || allowedOrigins.has(origin) || isDevLocalOrigin(origin)) {
      callback(null, true);
      return;
    }
    callback(new Error("Origen no permitido por CORS"));
  },
  credentials: true,
  methods: ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
  allowedHeaders: ["Content-Type", "Authorization"],
};
app.use(cors(corsOptions));
app.options(/.*/, cors(corsOptions));
app.use(helmet());
app.use(compression());
app.use(
  rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 300,
    standardHeaders: "draft-7",
    legacyHeaders: false,
    message: { ok: false, message: "Demasiadas solicitudes. Intenta nuevamente en unos minutos" },
  }),
);
app.use(express.json({ limit: "1mb" }));

const loginIpLimit = distributedRateLimit({
  name: "auth:login:ip",
  windowMs: 60_000,
  limit: 5,
  key: (req) => req.ip ?? "sin-ip",
});
const loginEmailLimit = distributedRateLimit({
  name: "auth:login:email",
  windowMs: 60_000,
  limit: 3,
  key: (req) => rateLimitDigest(String(req.body?.correo ?? "sin-correo").trim().toLowerCase()),
});
const passwordRecoveryLimit = distributedRateLimit({
  name: "auth:recuperacion",
  windowMs: 15 * 60_000,
  limit: 3,
  key: (req) =>
    rateLimitDigest(
      req.ip ?? "sin-ip",
      String(req.body?.correo ?? "sin-correo").trim().toLowerCase(),
    ),
});
const publicCatalogLimit = distributedRateLimit({
  name: "commerce:catalogo",
  windowMs: 60_000,
  limit: 60,
  key: (req) => req.ip ?? "sin-ip",
});
const uploadLimit = distributedRateLimit({
  name: "uploads",
  windowMs: 15 * 60_000,
  limit: 20,
  key: (req) => req.user?.sub ?? req.ip ?? "sin-ip",
});

app.use("/auth/login", loginIpLimit, loginEmailLimit);
app.use("/auth/recuperar-contrasena", passwordRecoveryLimit);
app.use("/commerce/catalogo", publicCatalogLimit);
app.set("json replacer", (_k: string, v: unknown) =>
  typeof v === "bigint" ? v.toString() : v,
);

/* --------------------------------- health -------------------------------- */
app.get("/", (_req: Request, res: Response) => {
  res.send("API viva");
});

app.get("/ping", async (_req: Request, res: Response, next: NextFunction) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    res.json({ ok: true });
  } catch (e) {
    next(e);
  }
});

/* -------------------------------- rutas ---------------------------------- */
app.use(authRequiredUnlessPublic);
app.use((req, res, next) => {
  if (!req.is("multipart/form-data")) {
    next();
    return;
  }
  uploadLimit(req, res, next);
});
app.use(rutas);

type ClientErrorPayload = {
  ok: false;
  message: string;
  error: string;
  code?: string;
  reason?: string;
  details?: unknown;
};

function fixMojibake(text: string) {
  const replacements: Array<[string, string]> = [
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

function normalizeBusinessMessage(rawMessage: string) {
  const clean = fixMojibake(rawMessage);
  if (!clean) return { message: "" };

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

function inferStatusFromMessage(message: string) {
  const normalized = message.toLowerCase();

  if (
    normalized.includes("no autenticado") ||
    normalized.includes("token requerido") ||
    normalized.includes("token invalido") ||
    normalized.includes("token expirado")
  ) {
    return 401;
  }

  if (normalized.includes("no autorizado")) {
    return 403;
  }

  if (
    normalized.includes("no encontrado") ||
    normalized.includes("no existe") ||
    normalized.includes("no registrada") ||
    normalized.includes("no registrado")
  ) {
    return 404;
  }

  if (
    normalized.includes("ya existe") ||
    normalized.includes("ya esta registrado") ||
    normalized.includes("ya se encuentra registrado")
  ) {
    return 409;
  }

  return 400;
}

function isSafeBusinessMessage(message: string) {
  const clean = message.trim();
  if (!clean) return false;

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

function sendError(
  res: Response,
  status: number,
  message: string,
  extra: { code?: string; details?: unknown } = {},
) {
  const payload: ClientErrorPayload = {
    ok: false,
    message,
    error: message,
    ...(extra.code ? { code: extra.code } : {}),
    ...(extra.details != null ? { details: extra.details } : {}),
  };

  res.status(status).json(payload);
}

/* ----------------------- middleware de error (tipado) --------------------- */
const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  console.error("[api-error]", {
    name: err instanceof Error ? err.name : "Error",
    status: typeof err?.status === "number" ? err.status : undefined,
    code: typeof err?.code === "string" ? err.code : undefined,
    ...(process.env.NODE_ENV !== "production" && err instanceof Error
      ? { message: fixMojibake(err.message) }
      : {}),
  });

  if (
    err &&
    typeof err === "object" &&
    (err as any).ok === false &&
    typeof (err as any).message === "string"
  ) {
    const status =
      typeof (err as any).status === "number"
        ? Number((err as any).status)
        : inferStatusFromMessage(String((err as any).message));

    res.status(status).json({
      ...(err as Record<string, unknown>),
      error:
        typeof (err as any).error === "string"
          ? (err as any).error
          : String((err as any).message),
    });
    return;
  }

  if (err instanceof ZodError || err?.name === "ZodError") {
    const issues = Array.isArray(err?.issues)
      ? err.issues
      : Array.isArray(err?.errors)
        ? err.errors
        : [];

    // El detalle tecnico queda solo en el log del servidor.
    console.error("[validacion] issues:", JSON.stringify(issues));

    const details = issues.map((issue: any) => ({
      field:
        Array.isArray(issue?.path) && issue.path.length > 0
          ? issue.path.join(".")
          : undefined,
      message: fixMojibake(mensajeValidacionAmigable(issue ?? {})),
    }));

    const primaryMessage =
      details.length === 1 && details[0].field
        ? `${details[0].message} (campo: ${details[0].field})`
        : details.length === 1
          ? details[0].message
          : "Revisa la informacion ingresada.";

    sendError(res, 400, primaryMessage, {
      code: "VALIDATION_ERROR",
      details,
    });
    return;
  }

  if (
    err instanceof Prisma.PrismaClientKnownRequestError &&
    err.code === "P2002"
  ) {
    const target = Array.isArray((err.meta as any)?.target)
      ? (err.meta as any).target.join(",")
      : String((err.meta as any)?.target ?? "");

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

  if (
    err instanceof Prisma.PrismaClientKnownRequestError &&
    err.code === "P2003"
  ) {
    const constraint = String((err.meta as any)?.constraint ?? "");

    if (constraint.includes("Tarea_ubicacionId_fkey")) {
      sendError(
        res,
        400,
        "No se pudo actualizar el conjunto porque hay tareas asociadas a ubicaciones existentes. Evita eliminar ubicaciones con tareas historicas.",
        { code: err.code },
      );
      return;
    }

    sendError(
      res,
      400,
      "No se pudo completar la operacion porque existen datos relacionados que lo impiden.",
      { code: err.code },
    );
    return;
  }

  if (
    err instanceof Prisma.PrismaClientKnownRequestError &&
    err.code === "P2025"
  ) {
    const cause = String((err.meta as any)?.cause ?? "").toLowerCase();

    if (cause.includes("supervisor")) {
      sendError(
        res,
        400,
        "No se pudo completar la operacion porque el supervisor seleccionado no existe. Actualiza la lista e intentalo nuevamente.",
        { code: err.code },
      );
      return;
    }

    sendError(
      res,
      400,
      "No se pudo completar la operacion porque faltan datos relacionados o ya no existen.",
      { code: err.code },
    );
    return;
  }

  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    sendError(
      res,
      500,
      "Ocurrio un error tecnico al procesar la solicitud. Si el problema continua, por favor contacta al area de TI.",
      { code: err.code },
    );
    return;
  }

  const rawStatus = typeof err?.status === "number" ? err.status : undefined;
  const normalized = normalizeBusinessMessage(String(err?.message ?? ""));

  if (rawStatus != null) {
    if (rawStatus >= 500 && !isSafeBusinessMessage(normalized.message)) {
      sendError(
        res,
        rawStatus,
        "Ocurrio un error inesperado. Si el problema continua, por favor contacta al area de TI.",
      );
      return;
    }

    sendError(
      res,
      rawStatus,
      normalized.message || "No se pudo completar la solicitud.",
      { code: normalized.code },
    );
    return;
  }

  if (normalized.message && isSafeBusinessMessage(normalized.message)) {
    sendError(
      res,
      inferStatusFromMessage(normalized.message),
      normalized.message,
      { code: normalized.code },
    );
    return;
  }

  sendError(
    res,
    500,
    "Ocurrio un error inesperado. Si el problema continua, por favor contacta al area de TI.",
  );
};

app.use(errorHandler);

/* ------------------------------- levantar server -------------------------- */
const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || "0.0.0.0";
(async () => {
  try {
    await bootstrapNotificacionesSchema(prisma);
    console.log("Notificaciones inicializadas");
  } catch (e) {
    console.error("No se pudo inicializar tabla de notificaciones:", e);
  }

  app.listen(PORT, HOST, () => {
    console.log(`API escuchando en http://${HOST}:${PORT}`);
  });
})();

/* -------------------------- cierre elegante Prisma ------------------------ */
process.on("SIGINT", async () => {
  await prisma.$disconnect();
  process.exit(0);
});
process.on("SIGTERM", async () => {
  await prisma.$disconnect();
  process.exit(0);
});

