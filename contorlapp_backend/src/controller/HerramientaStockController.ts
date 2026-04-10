import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import {
  ConjuntoNitParam,
  UpsertStockBody,
  AjustarStockBody,
  CambiarEstadoStockBody,
  EmpresaNitParam,
  DevolverPrestamoHerramientaBody,
} from "../model/Herramienta";
import { HerramientaStockService } from "../services/HerramientaStockService";
import { z } from "zod";

const HerramientaIdParam = z.object({
  herramientaId: z.coerce.number().int().positive(),
});

const DisponibilidadQuery = z.object({
  empresaId: z.string().min(3),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  excluirTareaId: z.coerce.number().int().positive().optional(),
});

export class HerramientaStockController {
  listarStockEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const { empresaId } = EmpresaNitParam.parse(req.params);
      const service = new HerramientaStockService(prisma, "");
      const out = await service.listarStockEmpresa(empresaId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  upsertStockEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const { empresaId } = EmpresaNitParam.parse(req.params);
      const body = UpsertStockBody.parse(req.body);
      const service = new HerramientaStockService(prisma, "");
      const out = await service.upsertStockEmpresa({
        empresaId,
        herramientaId: body.herramientaId,
        cantidad: Number(body.cantidad),
        estado: body.estado as any,
      });
      res.status(201).json(out);
    } catch (err) {
      next(err);
    }
  };

  ajustarStockEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const { empresaId } = EmpresaNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = AjustarStockBody.parse(req.body);
      const service = new HerramientaStockService(prisma, "");
      const out = await service.ajustarStockEmpresa({
        empresaId,
        herramientaId,
        delta: Number(body.delta),
        estado: body.estado as any,
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  eliminarStockEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const { empresaId } = EmpresaNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const service = new HerramientaStockService(prisma, "");
      await service.eliminarStockEmpresa({ empresaId, herramientaId });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  cambiarEstadoStockEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const { empresaId } = EmpresaNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = CambiarEstadoStockBody.parse(req.body);
      const service = new HerramientaStockService(prisma, "");
      const out = await service.cambiarEstadoStockEmpresa({
        empresaId,
        herramientaId,
        estadoActual: body.estadoActual as any,
        estadoNuevo: body.estadoNuevo as any,
        cantidad: Number(body.cantidad),
      });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  listarDisponibilidadConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const q = DisponibilidadQuery.parse(req.query);
      const service = new HerramientaStockService(prisma, nit);
      const out = await service.listarDisponibilidad({
        empresaId: q.empresaId,
        fechaInicio: q.fechaInicio,
        fechaFin: q.fechaFin,
        excluirTareaId: q.excluirTareaId,
      });
      res.json({ ok: true, data: out });
    } catch (err) {
      next(err);
    }
  };

  // GET /herramientas/conjunto/:nit/stock?estado=
  listarStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const estado = req.query.estado ? String(req.query.estado) : undefined;

      const service = new HerramientaStockService(prisma, nit);
      const out = await service.listarStock({ estado: estado as any });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // POST /herramientas/conjunto/:nit/stock  (upsert)
  upsertStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const body = UpsertStockBody.parse(req.body);

      const service = new HerramientaStockService(prisma, nit);
      const out = await service.upsertStock({
        herramientaId: body.herramientaId,
        cantidad: Number(body.cantidad),
        estado: body.estado as any,
      });

      res.status(201).json(out);
    } catch (err: any) {
      if (err?.code === "P2003") {
        (err as any).status = 409;
        (err as any).message = "Conjunto o herramienta no existe.";
      }
      next(err);
    }
  };

  // PATCH /herramientas/conjunto/:nit/stock/:herramientaId/ajustar
  ajustarStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = AjustarStockBody.parse(req.body);

      const service = new HerramientaStockService(prisma, nit);
      const out = await service.ajustarStock({
        herramientaId,
        delta: Number(body.delta),
        estado: body.estado as any,
      });

      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // DELETE /herramientas/conjunto/:nit/stock/:herramientaId?estado=
  eliminarStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const estado = (req.query.estado ? String(req.query.estado) : "OPERATIVA") as any;

      const service = new HerramientaStockService(prisma, nit);
      await service.eliminarStock({ herramientaId, estado });

      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  cambiarEstadoStockConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = CambiarEstadoStockBody.parse(req.body);

      const service = new HerramientaStockService(prisma, nit);
      const out = await service.cambiarEstadoStockConjunto({
        herramientaId,
        estadoActual: body.estadoActual as any,
        estadoNuevo: body.estadoNuevo as any,
        cantidad: Number(body.cantidad),
      });

      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  devolverPrestamoConjunto: RequestHandler = async (req, res, next) => {
    try {
      const { nit } = ConjuntoNitParam.parse(req.params);
      const { herramientaId } = HerramientaIdParam.parse(req.params);
      const body = DevolverPrestamoHerramientaBody.parse(req.body);

      const service = new HerramientaStockService(prisma, nit);
      const out = await service.devolverPrestamoConjunto({
        herramientaId,
        cantidad: Number(body.cantidad),
        estado: body.estado as any,
      });

      res.json(out);
    } catch (err) {
      next(err);
    }
  };
}
