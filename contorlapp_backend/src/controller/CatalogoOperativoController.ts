import { RequestHandler } from "express";
import { z } from "zod";

import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import { CatalogoOperativoService } from "../services/CatalogoOperativoService";

const service = new CatalogoOperativoService(prisma);

const IdParam = z.object({ id: z.coerce.number().int().positive() });
const Rol = z.enum(["TODERO", "SALVAVIDAS", "ASEO", "PISCINERO", "JARDINERO"]);

const CrearCategoriaBody = z.object({
  nombre: z.string().min(1).max(80),
  colorHex: z.string().nullable().optional(),
  icono: z.string().max(40).nullable().optional(),
  palabrasClave: z.array(z.string().max(60)).max(50).optional(),
});

const EditarCategoriaBody = z.object({
  nombre: z.string().min(1).max(80).optional(),
  colorHex: z.string().nullable().optional(),
  icono: z.string().max(40).nullable().optional(),
  palabrasClave: z.array(z.string().max(60)).max(50).optional(),
  activa: z.boolean().optional(),
});

const OrdenCategoriasBody = z.object({
  ids: z.array(z.number().int().positive()).min(1),
});

const CrearPerfilBody = z.object({
  nombre: z.string().min(1).max(80),
  roles: z.array(Rol).min(1),
  descripcion: z.string().max(300).nullable().optional(),
  categoriasIds: z.array(z.number().int().positive()).optional(),
});

const EditarPerfilBody = z.object({
  nombre: z.string().min(1).max(80).optional(),
  roles: z.array(Rol).min(1).optional(),
  descripcion: z.string().max(300).nullable().optional(),
  activo: z.boolean().optional(),
  categoriasIds: z.array(z.number().int().positive()).optional(),
});

export class CatalogoOperativoController {
  listarCategorias: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      res.json(await service.listarCategorias(empresaId));
    } catch (err) {
      next(err);
    }
  };

  crearCategoria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const body = CrearCategoriaBody.parse(req.body);
      res.status(201).json(await service.crearCategoria(empresaId, body));
    } catch (err) {
      next(err);
    }
  };

  editarCategoria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = IdParam.parse(req.params);
      const body = EditarCategoriaBody.parse(req.body);
      res.json(await service.editarCategoria(empresaId, id, body));
    } catch (err) {
      next(err);
    }
  };

  reordenarCategorias: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { ids } = OrdenCategoriasBody.parse(req.body);
      res.json(await service.reordenarCategorias(empresaId, ids));
    } catch (err) {
      next(err);
    }
  };

  eliminarCategoria: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = IdParam.parse(req.params);
      res.json(await service.eliminarCategoria(empresaId, id));
    } catch (err) {
      next(err);
    }
  };

  listarPerfiles: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      res.json(await service.listarPerfiles(empresaId));
    } catch (err) {
      next(err);
    }
  };

  crearPerfil: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const body = CrearPerfilBody.parse(req.body);
      res.status(201).json(await service.crearPerfil(empresaId, body));
    } catch (err) {
      next(err);
    }
  };

  editarPerfil: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = IdParam.parse(req.params);
      const body = EditarPerfilBody.parse(req.body);
      res.json(await service.editarPerfil(empresaId, id, body));
    } catch (err) {
      next(err);
    }
  };

  eliminarPerfil: RequestHandler = async (req, res, next) => {
    try {
      const empresaId = await empresaIdAutenticada(req);
      const { id } = IdParam.parse(req.params);
      res.json(await service.eliminarPerfil(empresaId, id));
    } catch (err) {
      next(err);
    }
  };
}
