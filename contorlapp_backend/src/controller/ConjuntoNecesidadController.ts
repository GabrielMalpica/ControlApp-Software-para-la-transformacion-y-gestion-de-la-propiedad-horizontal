// src/controller/ConjuntoNecesidadController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { ConjuntoNecesidadService } from "../services/ConjuntoNecesidadService";

const NitSchema = z.object({ nit: z.string().min(3) });
const NecesidadIdSchema = z.object({ necesidadId: z.coerce.number().int().positive() });
const ConfirmarQuery = z.object({
  confirmar: z
    .union([z.literal("true"), z.literal("false")])
    .optional()
    .transform((v) => v === "true"),
});

function resolveConjuntoId(req: any): string {
  const parsed = NitSchema.safeParse({ nit: req.params?.nit });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el NIT del conjunto.");
    e.status = 400;
    throw e;
  }
  return parsed.data.nit;
}

function resolveNecesidadId(req: any): number {
  const parsed = NecesidadIdSchema.safeParse({ necesidadId: req.params?.necesidadId });
  if (!parsed.success) {
    const e: any = new Error("Falta o es inválido el id de la necesidad.");
    e.status = 400;
    throw e;
  }
  return parsed.data.necesidadId;
}

export class ConjuntoNecesidadController {
  // GET /conjuntos/:nit/necesidades
  listar: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.listar();
      res.json(data);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/necesidades
  crear: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.crear(req.body);
      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /conjuntos/:nit/necesidades/:necesidadId
  editar: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const necesidadId = resolveNecesidadId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.editar(necesidadId, req.body);
      res.json(data);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /conjuntos/:nit/necesidades/:necesidadId?confirmar=true
  eliminar: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const necesidadId = resolveNecesidadId(req);
      const { confirmar } = ConfirmarQuery.parse(req.query);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const result = await service.eliminar(necesidadId, { confirmar });

      if (!result.ok && result.requiresConfirmation) {
        res.status(409).json(result);
        return;
      }
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/necesidades/:necesidadId/operario
  asignarOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const necesidadId = resolveNecesidadId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.asignarOperario(necesidadId, req.body);
      res.json(data);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /conjuntos/:nit/necesidades/:necesidadId/operario
  liberarOperario: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const necesidadId = resolveNecesidadId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.liberarOperario(necesidadId);
      res.json(data);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/necesidades/migrar-desde-operarios
  migrarDesdeOperariosActuales: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.migrarDesdeOperariosActuales();
      res.status(201).json(data);
    } catch (err) {
      next(err);
    }
  };

  // POST /conjuntos/:nit/necesidades/vincular-definiciones
  vincularDefinicionesConNecesidades: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = resolveConjuntoId(req);
      const service = new ConjuntoNecesidadService(prisma, conjuntoId);
      const data = await service.vincularDefinicionesConNecesidades();
      res.status(200).json(data);
    } catch (err) {
      next(err);
    }
  };
}
