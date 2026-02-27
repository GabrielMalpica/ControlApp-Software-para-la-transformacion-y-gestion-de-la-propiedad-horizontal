// src/index.ts
import "dotenv/config";
import express, {
  Request,
  Response,
  NextFunction,
  ErrorRequestHandler,
} from "express";
import cors from "cors";
import { Prisma } from "@prisma/client";
import rutas from "./routes/Rutas";
import { prisma } from "./db/prisma";
import { bootstrapNotificacionesSchema } from "./services/NotificacionService";

if (!process.env.JWT_SECRET) {
  throw new Error("Falta JWT_SECRET en el archivo .env");
}

const app = express();
app.use(cors());
app.use(express.json());

app.set("json replacer", (_k: string, v: unknown) =>
  typeof v === "bigint" ? v.toString() : v,
);

/* --------------------------------- health -------------------------------- */
app.get("/", (_req: Request, res: Response) => {
  res.send("API viva");
});

app.get("/ping", async (_req: Request, res: Response, next: NextFunction) => {
  try {
    const count = await prisma.empresa.count();
    res.json({ ok: true, empresaPublicSelect: count });
  } catch (e) {
    next(e);
  }
});

/* -------------------------------- rutas ---------------------------------- */
app.use(rutas);

/* ----------------------- middleware de error (tipado) --------------------- */
const errorHandler: ErrorRequestHandler = (err, _req, res, _next) => {
  console.error("Error:", err);

  // Zod
  if (err?.name === "ZodError") {
    res.status(400).json({ error: err.issues ?? err.errors });
    return;
  }

  // Prisma unique constraint
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2002") {
    const target = Array.isArray((err.meta as any)?.target)
      ? (err.meta as any).target.join(",")
      : String((err.meta as any)?.target ?? "");

    if (target.includes("Conjunto") || target.includes("nit")) {
      res.status(409).json({ error: "Ya existe un conjunto con ese NIT." });
      return;
    }

    res.status(409).json({ error: "El registro ya existe y debe ser único." });
    return;
  }


  // Prisma foreign key constraint
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2003") {
    const constraint = String((err.meta as any)?.constraint ?? "");

    if (constraint.includes("Tarea_ubicacionId_fkey")) {
      res.status(400).json({
        error:
          "No se pudo actualizar el conjunto porque hay tareas asociadas a ubicaciones existentes. Evita eliminar ubicaciones con tareas históricas.",
      });
      return;
    }

    res.status(400).json({
      error:
        "No se pudo completar la operación porque existen datos relacionados que lo impiden.",
    });
    return;
  }

  // Prisma registro relacionado/no encontrado
  if (err instanceof Prisma.PrismaClientKnownRequestError && err.code === "P2025") {
    const cause = String((err.meta as any)?.cause ?? "").toLowerCase();

    if (cause.includes("supervisor")) {
      res.status(400).json({
        error:
          "No se pudo completar la operación porque el supervisor seleccionado no existe. Actualiza la lista e inténtalo nuevamente.",
      });
      return;
    }

    res.status(400).json({
      error:
        "No se pudo completar la operación porque faltan datos relacionados o ya no existen.",
    });
    return;
  }

  // Otros errores Prisma: no exponer detalles técnicos
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    res.status(500).json({
      error:
        "Ocurrió un error técnico al procesar la solicitud. Si el problema continúa, por favor contacta al área de TI.",
    });
    return;
  }

  // Si en tu codigo lanzas e.status, respetalo
  const status = typeof err?.status === "number" ? err.status : 500;
  if (status >= 500) {
    res.status(status).json({
      error:
        "Ocurrió un error inesperado. Si el problema continúa, por favor contacta al área de TI.",
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
    await bootstrapNotificacionesSchema(prisma);
    console.log("Notificaciones inicializadas");
  } catch (e) {
    console.error("No se pudo inicializar tabla de notificaciones:", e);
  }

  app.listen(PORT, () => {
    console.log(`API escuchando en http://localhost:${PORT}`);
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
