// src/index.ts
import "dotenv/config";
import express, {
  Request,
  Response,
  NextFunction,
  ErrorRequestHandler,
} from "express";
import cors from "cors";
import rutas from "./routes/Rutas";
import { prisma } from "./db/prisma";
import { bootstrapNotificacionesSchema } from "./services/NotificacionService";
import { bootstrapUsuariosIniciales } from "./services/bootstrapUsuariosIniciales";

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

  // Si en tu codigo lanzas e.status, respetalo
  const status = typeof err?.status === "number" ? err.status : 500;
  res.status(status).json({ error: err?.message ?? "Error interno" });
};

app.use(errorHandler);

/* ------------------------------- levantar server -------------------------- */
const PORT = 3000;
(async () => {
  try {
    await bootstrapUsuariosIniciales(prisma);
    console.log("Usuarios iniciales verificados");
  } catch (e) {
    console.error("No se pudieron bootstrapear usuarios iniciales:", e);
  }

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
