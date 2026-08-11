import { Router } from "express";
import { GerenteService } from "../services/GerenteServices";
import { prisma } from "../db/prisma";
import { authRequired } from "../middlewares/auth.middleware";
import { requirePermission } from "../middlewares/permission.middleware";
import { requireRoles } from "../middlewares/role.middleware";
import { requireConjuntoScope, requireResourceScope } from "../middlewares/tenant.middleware";

const router = Router();

router.use(authRequired);
router.use(requireRoles("gerente", "jefe_operaciones", "supervisor"));

// Crear correctiva
router.post("/conjuntos/:nit/tareas", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireConjuntoScope("nit"), async (req, res, next) => {
  try {
    const conjuntoId = req.params.nit;
    const svc = new GerenteService(prisma, req.user?.empresaId);
    const out = await svc.asignarTarea({ ...req.body, conjuntoId, tipo: "CORRECTIVA" });
    res.status(201).json(out);
  } catch (e) { next(e); }
});

// Editar correctiva
router.patch("/tareas/:id", requirePermission("tareas.crear", "cronograma.correctivas_programar"), requireResourceScope("tarea", "id"), async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    const svc = new GerenteService(prisma, req.user?.empresaId);
    const out = await svc.editarTarea(id, req.body); // aquí puedes validar estado/solapes
    res.json(out);
  } catch (e) { next(e); }
});


// Listar por rango (mixto o filtra tipo)
router.get("/conjuntos/:nit/tareas", requirePermission("tareas.ver"), requireConjuntoScope("nit"), async (req, res, next) => {
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
