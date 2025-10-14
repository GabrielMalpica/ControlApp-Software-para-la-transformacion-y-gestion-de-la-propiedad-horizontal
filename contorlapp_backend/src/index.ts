// src/index.ts
import express, { Request, Response, NextFunction } from "express";
import { PrismaClient } from "./generated/prisma";

const app = express();
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
  const count = await prisma.conjunto.count();
  res.json({ ok: true, conjuntos: count });
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

/* ------------------------------ Rutas de NIT ------------------------------ */

/**
 * 1) Operarios asignados a un conjunto
 * GET /conjuntos/:nit/operarios
 */
app.get(
  "/conjuntos/:nit/operarios",
  async (req: Request<{ nit: string }>, res: Response): Promise<void> => {
    const nit = ensureNit(req, res);
    if (!nit) return;

    const conjunto = await prisma.conjunto.findUnique({
      where: { nit },
      select: {
        nit: true,
        nombre: true,
        operarios: {
          include: { usuario: { select: { id: true, nombre: true, correo: true, telefono: true } } },
        },
      },
    });

    if (!conjunto) {
      res.status(404).json({ error: "Conjunto no encontrado" });
      return;
    }

    const data = conjunto.operarios.map((op) => ({
      id: op.id,
      nombre: op.usuario?.nombre ?? "—",
      correo: op.usuario?.correo ?? "—",
      telefono: op.usuario?.telefono ?? null,
      funciones: op.funciones,
      fechaIngreso: op.fechaIngreso,
      fechaSalida: op.fechaSalida,
    }));

    res.json({ conjunto: { nit: conjunto.nit, nombre: conjunto.nombre }, operarios: data });
  }
);


/**
 * 2) Administrador del conjunto
 * GET /conjuntos/:nit/administrador
 */
app.get(
  "/conjuntos/:nit/administrador",
  async (req: Request<{ nit: string }>, res: Response): Promise<void> => {
    const nit = ensureNit(req, res);
    if (!nit) return;

    const conjunto = await prisma.conjunto.findUnique({
      where: { nit },
      select: {
        nit: true,
        nombre: true,
        administrador: {
          include: { usuario: { select: { id: true, nombre: true, correo: true, telefono: true } } },
        },
      },
    });

    if (!conjunto) {
      res.status(404).json({ error: "Conjunto no encontrado" });
      return;
    }

    const admin = conjunto.administrador
      ? {
          id: conjunto.administrador.id,
          nombre: conjunto.administrador.usuario?.nombre ?? "—",
          correo: conjunto.administrador.usuario?.correo ?? "—",
          telefono: conjunto.administrador.usuario?.telefono ?? null,
        }
      : null;

    res.json({ conjunto: { nit: conjunto.nit, nombre: conjunto.nombre }, administrador: admin });
  }
);


/**
 * 3) Maquinaria asignada al conjunto
 * GET /conjuntos/:nit/maquinaria
 */
app.get("/conjuntos/:nit/maquinaria", async (req, res) => {
  const nit = ensureNit(req, res);
  if (!nit) return;

  const maquinaria = await prisma.maquinaria.findMany({
    where: { conjuntoId: nit },
    select: {
      id: true,
      nombre: true,
      marca: true,
      tipo: true,
      estado: true,
      disponible: true,
      fechaPrestamo: true,
      fechaDevolucionEstimada: true,
      responsable: { include: { usuario: { select: { nombre: true } } } },
    },
  });

  res.json(
    maquinaria.map((m) => ({
      id: m.id,
      nombre: m.nombre,
      marca: m.marca,
      tipo: m.tipo,
      estado: m.estado,
      disponible: m.disponible,
      responsable: m.responsable?.usuario?.nombre ?? "Sin asignar",
      fechaPrestamo: m.fechaPrestamo,
      fechaDevolucionEstimada: m.fechaDevolucionEstimada,
    }))
  );
});

/**
 * 4) Inventario (insumos) del conjunto
 * GET /conjuntos/:nit/inventario
 */
app.get(
  "/conjuntos/:nit/inventario",
  async (req: Request<{ nit: string }>, res: Response): Promise<void> => {
    const nit = ensureNit(req, res);
    if (!nit) return;

    const inventario = await prisma.inventario.findUnique({
      where: { conjuntoId: nit },
      include: {
        insumos: { include: { insumo: true } },
        consumos: {
          orderBy: { fecha: "desc" },
          take: 20,
          include: { insumo: true, tarea: { select: { id: true, descripcion: true } } },
        },
        conjunto: { select: { nit: true, nombre: true } },
      },
    });

    if (!inventario) {
      res.status(404).json({ error: "Inventario no encontrado para ese conjunto" });
      return;
    }

    const stock = inventario.insumos.map((ii) => ({
      inventarioInsumoId: ii.id,
      insumoId: ii.insumoId,
      nombre: ii.insumo.nombre,
      unidad: ii.insumo.unidad,
      cantidad: ii.cantidad,
    }));

    const ultimosConsumos = inventario.consumos.map((c) => ({
      id: c.id,
      insumo: c.insumo.nombre,
      cantidad: c.cantidad,
      fecha: c.fecha,
      tareaId: c.tareaId,
      tarea: c.tarea?.descripcion ?? null,
      observacion: c.observacion ?? null,
    }));

    res.json({
      conjunto: inventario.conjunto,
      inventarioId: inventario.id,
      stock,
      ultimosConsumos,
    });
  }
);


/* ------------------------------- levantar server ------------------------------ */
const PORT = 3000;
app.listen(PORT, () => {
  console.log(`🟢 API escuchando en http://localhost:${PORT}`);
});
