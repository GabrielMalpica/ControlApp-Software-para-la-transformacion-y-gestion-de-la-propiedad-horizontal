// src/index.ts
import express, { Request, Response, NextFunction } from "express";
import { PrismaClient } from "./generated/prisma";
import cors from 'cors';
import "./utils/cron";
import rutas from "./routes/Rutas";
import { empresaPublicSelect } from "./model/Empresa";

const app = express();
app.use(cors());
app.use(express.json());
app.set(
  "json replacer",
  (_key: string, value: unknown): unknown =>
    typeof value === "bigint" ? value.toString() : value
);


const prisma = new PrismaClient();

/* -------------------------- middlewares de error -------------------------- */
app.use((err: any, _req: Request, res: Response, _next: NextFunction): void => {
  console.error("❌ Error:", err);
  if (err?.name === "ZodError") {
    res.status(400).json({ error: err.errors });
    return;
  }
  res.status(500).json({ error: err?.message ?? "Error interno" });
});


/* --------------------------------- health -------------------------------- */
app.get("/", (_req, res) => {
  res.send("🚀 API viva");
});

app.get("/ping", async (_req, res) => {
  const count = await prisma.empresa.count();
  res.json({ ok: true, empresaPublicSelect: count });
});
app.use(rutas);

app.use((err: any, _req: Request, res: Response, _next: NextFunction): void => {
  console.error("❌ Error:", err);

  if (err?.name === "ZodError") {
    console.error("🟥 Zod issues:", err.issues);
    res.status(400).json({ error: err.issues });
    return;
  }

  res.status(500).json({ error: err?.message ?? "Error interno" });
});

/* --------------------------- helpers muy simples -------------------------- */
function ensureNit(req: Request, res: Response): string | undefined {
  const nit = String(req.params.nit ?? "").trim();
  if (!nit) {
    res.status(400).json({ error: "Debes enviar el NIT del conjunto en la ruta." });
    return;
  }
  return nit;
}

/* ------------------------------- levantar server ------------------------------ */
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 API escuchando en http://localhost:${PORT}`);
});
