// src/controllers/ConjuntoController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { ConjuntoService } from "../services/ConjuntoServices";
import { CronogramaService } from "../services/CronogramaServices";

/* ===================== Schemas mínimos ===================== */
const NitSchema = z.object({ nit: z.string().min(3) });
const OperarioIdSchema = z.object({
  operarioId: z.coerce.number().int().positive(),
});
const AdminIdSchema = z.object({
  administradorId: z.coerce.number().int().positive(),
});
const MaquinariaIdSchema = z.object({
  maquinariaId: z.coerce.number().int().positive(),
});
const TareaIdSchema = z.object({ tareaId: z.coerce.number().int().positive() });
const FechaSchema = z.object({ fecha: z.coerce.date() });
const UbicacionNombreSchema = z.object({ nombreUbicacion: z.string().min(1) });

const SetActivoBody = z.object({ activo: z.boolean() });

const RangoQuery = z
  .object({
    fechaInicio: z.coerce.date(),
    fechaFin: z.coerce.date(),
  })
  .refine((d) => d.fechaFin >= d.fechaInicio, {
    path: ["fechaFin"],
    message: "fechaFin debe ser >= fechaInicio",
  });

const TareasPorFiltroQuery = z
  .object({
    operarioId: z.coerce.number().int().positive().optional(),
    fechaExacta: z.coerce.date().optional(),
    fechaInicio: z.coerce.date().optional(),
    fechaFin: z.coerce.date().optional(),
    ubicacion: z.string().optional(),
  })
  .refine(
    (d) => {
      if (d.fechaExacta) return true;
      // si no hay fechaExacta, entonces ambos extremos o ninguno
      return (
        (!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin))
      );
    },
    { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." }
  );

/* ===================== Helpers ===================== */
function resolveConjuntoId(req: any): string {
  const headerNit = (
    req.header?.("x-conjunto-id") ?? req.header?.("x-nit")
  )?.trim();
  const queryNit =
    typeof req.query?.nit === "string" ? req.query.nit : undefined;
  const paramsNit = req.params?.nit as string | undefined;
  const nit = headerNit || queryNit || paramsNit;
  const parsed = NitSchema.safeParse({ nit });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el NIT del conjunto.");
    e.status = 400;
    throw e;
  }
  return parsed.data.nit;
}

/* ===================== Controller ===================== */
export class ConjuntoController {
  constructor(private prisma: PrismaClient) {}

  // PUT /conjuntos/:nit/activo
  setActivo: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const { activo } = SetActivoBody.parse(req.body);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      await service.setActivo(activo);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/operarios
  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const body = OperarioIdSchema.parse(req.body);
      await service.asignarOperario(body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // PUT /conjuntos/:nit/administrador
  asignarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const body = AdminIdSchema.parse(req.body);
      await service.asignarAdministrador(body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // DELETE /conjuntos/:nit/administrador
  eliminarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      await service.eliminarAdministrador();
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/maquinaria
  agregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const body = MaquinariaIdSchema.parse(req.body);
      await service.agregarMaquinaria(body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/maquinaria/entregar
  entregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const body = MaquinariaIdSchema.parse(req.body);
      await service.entregarMaquinaria(body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/ubicaciones
  agregarUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      await service.agregarUbicacion(req.body); // valida internamente con CrearUbicacionDTO
      res.status(201).json({ message: "Ubicación registrada (o ya existía)." });
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/ubicaciones/buscar?nombre=...
  buscarUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const nombre = (req.query.nombre ?? req.query.nombreUbicacion) as
        | string
        | undefined;
      const payload = UbicacionNombreSchema.parse({ nombreUbicacion: nombre });
      const result = await service.buscarUbicacion({
        nombre: payload.nombreUbicacion,
      });
      if (!result) {
        res.status(404).json({ message: "Ubicación no encontrada" });
        return;
      }
      res.json(result);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/cronograma/tareas
  agregarTareaACronograma: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const body = TareaIdSchema.parse(req.body);
      await service.agregarTareaACronograma(body);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/tareas/por-fecha?fecha=YYYY-MM-DD
  tareasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const { fecha } = FechaSchema.parse({
        fecha: req.query.fecha as string | undefined,
      });
      const tareas = await service.tareasPorFecha({ fecha });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/tareas/por-operario/:operarioId
  tareasPorOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const { operarioId } = OperarioIdSchema.parse(req.params);
      const tareas = await service.tareasPorOperario({ operarioId });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/tareas/por-ubicacion?nombreUbicacion=...
  tareasPorUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const payload = UbicacionNombreSchema.parse({
        nombreUbicacion: req.query.nombreUbicacion,
      });
      const tareas = await service.tareasPorUbicacion({
        nombreUbicacion: payload.nombreUbicacion,
      });
      res.json(tareas);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/tareas/en-rango?fechaInicio=...&fechaFin=...
  tareasEnRango: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const cronograma = new CronogramaService(this.prisma, conjuntoId); // ⬅️ usar CronogramaService
      const { fechaInicio, fechaFin } = RangoQuery.parse({
        fechaInicio: req.query.fechaInicio,
        fechaFin: req.query.fechaFin,
      });
      const out = await cronograma.tareasEnRango({ fechaInicio, fechaFin });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/tareas/filtrar?... (operarioId?, fechaExacta? o rango, ubicacion?)
  tareasPorFiltro: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const cronograma = new CronogramaService(this.prisma, conjuntoId); // ⬅️ usar CronogramaService
      const filtro = TareasPorFiltroQuery.parse(req.query);
      const out = await cronograma.tareasPorFiltro(filtro);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /conjuntos/:nit/cronograma/eventos-calendario
  exportarEventosCalendario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const cronograma = new CronogramaService(this.prisma, conjuntoId); // ⬅️ usar CronogramaService
      const eventos = await cronograma.exportarComoEventosCalendario();
      res.json(eventos);
    } catch (err) {
      next(err);
    }
  };
}
