import { Router } from "express";
import { GerenteService } from "../services/GerenteServices";
import { PrismaClient } from "../generated/prisma";

const prisma = new PrismaClient();
const svc = new GerenteService(prisma);
const router = Router();

// Crear correctiva
router.post("/conjuntos/:nit/tareas", async (req, res, next) => {
  try {
    const conjuntoId = req.params.nit;
    const out = await svc.asignarTarea({ ...req.body, conjuntoId, tipo: "CORRECTIVA" });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Editar correctiva
router.patch("/tareas/:id", async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const out = await svc.editarTarea(id, req.body); // aquí puedes validar estado/solapes
    res.json(out);
  } catch (e) { next(e); }
});

// Eliminar correctiva
router.delete("/tareas/:id", async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    await svc.eliminarTarea(id);
    res.status(204).send();
  } catch (e) { next(e); }
});

// Listar por rango (mixto o filtra tipo)
router.get("/conjuntos/:nit/tareas", async (req, res, next) => {
  try {
    const conjuntoId = req.params.nit;
    const { desde, hasta, tipo } = req.query as any;
    const where: any = {
      conjuntoId,
      ...(tipo ? { tipo } : {}),
      ...(desde || hasta ? { fechaFin: { gte: new Date(desde) }, fechaInicio: { lte: new Date(hasta) } } : {}),
    };
    const list = await prisma.tarea.findMany({ where, orderBy: [{ fechaInicio: "asc" }] });
    res.json(list);
  } catch (e) { next(e); }
});

export default router;
