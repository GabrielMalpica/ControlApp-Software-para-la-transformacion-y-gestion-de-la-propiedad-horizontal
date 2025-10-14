// src/controllers/ConjuntoController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { PrismaClient } from "../generated/prisma";
import { ConjuntoService } from "../services/ConjuntoServices";

// Schemas mínimos para params/query/headers
const NitSchema = z.object({ nit: z.string().min(3) });
const OperarioIdSchema = z.object({ operarioId: z.coerce.number().int().positive() });
const AdminIdSchema = z.object({ administradorId: z.coerce.number().int().positive() });
const MaquinariaIdSchema = z.object({ maquinariaId: z.coerce.number().int().positive() });
const TareaIdSchema = z.object({ tareaId: z.coerce.number().int().positive() });
const FechaSchema = z.object({ fecha: z.coerce.date() });
const UbicacionNombreSchema = z.object({ nombreUbicacion: z.string().min(1) });

// Resolver del NIT (conjuntoId)
function resolveConjuntoId(req: any): string {
  const headerNit = (req.header("x-conjunto-id") ?? req.header("x-nit"))?.trim();
  const queryNit = typeof req.query.nit === "string" ? req.query.nit : undefined;
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

export class ConjuntoController {
  private prisma: PrismaClient;
  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
  }

  // POST /conjuntos/:nit/operarios
  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      // Body: { operarioId: number }
      const body = OperarioIdSchema.parse(req.body);
      await service.asignarOperario(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // PUT /conjuntos/:nit/administrador
  asignarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      // Body: { administradorId: number }
      const body = AdminIdSchema.parse(req.body);
      await service.asignarAdministrador(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // DELETE /conjuntos/:nit/administrador
  eliminarAdministrador: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      await service.eliminarAdministrador();
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /conjuntos/:nit/maquinaria
  agregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      // Body: { maquinariaId: number }
      const body = MaquinariaIdSchema.parse(req.body);
      await service.agregarMaquinaria(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /conjuntos/:nit/maquinaria/entregar
  entregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      // Body: { maquinariaId: number }
      const body = MaquinariaIdSchema.parse(req.body);
      await service.entregarMaquinaria(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // POST /conjuntos/:nit/ubicaciones
  agregarUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      await service.agregarUbicacion(req.body); // el service valida con CrearUbicacionDTO
      res.status(201).json({ message: "Ubicación registrada (o ya existía)." });
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/ubicaciones/buscar?nombre=...
  buscarUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);
      const nombre = (req.query.nombre ?? req.query.nombreUbicacion) as string | undefined;

      const payload = UbicacionNombreSchema.parse({ nombreUbicacion: nombre });
      const result = await service.buscarUbicacion({ nombre: payload.nombreUbicacion });
      if (!result) { res.status(404).json({ message: "Ubicación no encontrada" }); return; }
      res.json(result);
    } catch (err) { next(err); }
  };

  // POST /conjuntos/:nit/cronograma/tareas
  agregarTareaACronograma: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      // Body: { tareaId: number }
      const body = TareaIdSchema.parse(req.body);
      await service.agregarTareaACronograma(body);
      res.status(204).send();
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/tareas/por-fecha?fecha=YYYY-MM-DD
  tareasPorFecha: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      const fechaStr = req.query.fecha as string | undefined;
      const { fecha } = FechaSchema.parse({ fecha: fechaStr });
      const tareas = await service.tareasPorFecha({ fecha });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/tareas/por-operario/:operarioId
  tareasPorOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      const { operarioId } = OperarioIdSchema.parse(req.params);
      const tareas = await service.tareasPorOperario({ operarioId });
      res.json(tareas);
    } catch (err) { next(err); }
  };

  // GET /conjuntos/:nit/tareas/por-ubicacion?nombreUbicacion=...
  tareasPorUbicacion: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoService(this.prisma, conjuntoId);

      const payload = UbicacionNombreSchema.parse({ nombreUbicacion: req.query.nombreUbicacion });
      const tareas = await service.tareasPorUbicacion({ nombreUbicacion: payload.nombreUbicacion });
      res.json(tareas);
    } catch (err) { next(err); }
  };
}
