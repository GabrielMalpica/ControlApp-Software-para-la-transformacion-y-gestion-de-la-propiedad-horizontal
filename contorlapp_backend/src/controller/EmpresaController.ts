// src/controllers/EmpresaController.ts
import { RequestHandler } from "express";
import { z } from "zod";
import { prisma } from "../db/prisma";
import { EmpresaService } from "../services/EmpresaServices";

const IdParamSchema = z.object({ id: z.coerce.number().int().positive() });
const NitHeaderSchema = z.object({ nit: z.string().min(3) });

function resolveEmpresaId(req: any): string {
  const headersNit = (
    req.header("x-empresa-id") ?? req.header("x-nit")
  )?.trim();
  const queryNit =
    typeof req.query.nit === "string" ? req.query.nit : undefined;
  const paramsNit = req.params?.nit as string | undefined;

  const nit = headersNit || queryNit || paramsNit;
  if (!nit) {
    // lanza con status para que tu error middleware lo tome
    const e: any = new Error("Falta el NIT de la empresa.");
    e.status = 400;
    throw e;
  }
  return NitHeaderSchema.parse({ nit }).nit;
}

export class EmpresaController {
  crearEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const service = new EmpresaService("901191875-4");
      const creada = await service.crearEmpresa(req.body);
      res.status(201).json(creada);
    } catch (err) {
      next(err);
    }
  };

  getLimiteMinSemanaPorConjunto: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { nit } = req.params;

      const service = new EmpresaService(empresaId);
      const out = await service.getLimiteMinSemanaPorConjunto(nit);

      res.status(200).json({ limiteMinSemana: out });
    } catch (err) {
      next(err);
    }
  };

  listarFestivos: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);

      const { desde, hasta, pais } = req.query as any;
      const out = await service.listarFestivos(desde, hasta, pais ?? "CO");
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  reemplazarFestivosEnRango: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);

      const out = await service.reemplazarFestivosEnRango(req.body);
      res.status(200).json(out);
    } catch (err) {
      next(err);
    }
  };

  agregarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const creada = await service.agregarMaquinaria(req.body);
      res.status(201).json(creada);
    } catch (err) {
      next(err);
    }
  };

  listarMaquinariaCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const items = await service.listarMaquinariaCatalogo(req.query);
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  editarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      const upd = await service.editarMaquinaria(id, req.body);
      res.json(upd);
    } catch (err) {
      next(err);
    }
  };

  eliminarMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      await service.eliminarMaquinaria(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  listarMaquinariaDisponible: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const items = await service.listarMaquinariaDisponible();
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  obtenerMaquinariaPrestada: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const items = await service.obtenerMaquinariaPrestada();
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  agregarJefeOperaciones: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const jefe = await service.agregarJefeOperaciones(req.body);
      res.status(201).json(jefe);
    } catch (err) {
      next(err);
    }
  };

  recibirSolicitudTarea: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      const upd = await service.recibirSolicitudTarea({ id });
      res.json(upd);
    } catch (err) {
      next(err);
    }
  };

  eliminarSolicitudTarea: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      await service.eliminarSolicitudTarea({ id });
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };

  solicitudesTareaPendientes: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const list = await service.solicitudesTareaPendientes();
      res.json(list);
    } catch (err) {
      next(err);
    }
  };

  agregarInsumoAlCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const insumo = await service.agregarInsumoAlCatalogo(req.body);
      res.status(201).json(insumo);
    } catch (err) {
      next(err);
    }
  };

  listarCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const service = new EmpresaService(empresaId);
      const items = await service.listarCatalogo(req.query); // opcional
      res.json(items);
    } catch (err) {
      next(err);
    }
  };

  buscarInsumoPorId: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      const item = await service.buscarInsumoPorId({ id });
      if (!item) {
        res.status(404).json({ message: "Insumo no encontrado" });
        return;
      }
      res.json(item);
    } catch (err) {
      next(err);
    }
  };

  editarInsumoCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      const upd = await service.editarInsumoCatalogo(id, req.body);
      res.json(upd);
    } catch (err) {
      next(err);
    }
  };

  eliminarInsumoCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = resolveEmpresaId(req);
      const { id } = IdParamSchema.parse(req.params);
      const service = new EmpresaService(empresaId);
      await service.eliminarInsumoCatalogo(id);
      res.status(204).send();
    } catch (err) {
      next(err);
    }
  };
}
