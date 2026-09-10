import fs from "fs";
import { Request, RequestHandler } from "express";
import { PropietarioMaquinaria } from "@prisma/client";

import { prisma } from "../db/prisma";
import { empresaIdAutenticada } from "../middlewares/tenant.middleware";
import {
  AprobarActivoBody,
  CambiarEstadoHerramientaBody,
  CambiarEstadoMaquinariaBody,
  CrearHerramientasInventarioBody,
  CrearMaquinariaInventarioBody,
  EditarActivoBody,
  IdActivoParam,
  ListaHerramientasQuery,
  ListaMaquinariaQuery,
  LoteActivoParam,
  PrestarActivoBody,
  RechazarActivoBody,
} from "../model/InventarioActivo";
import { InventarioActivoService } from "../services/InventarioActivoService";
import { extraerActorAuditoriaConNombre } from "../utils/auditoria";

type Kind = "maquinaria" | "herramienta";

export class InventarioActivoController {
  private async service(req: Request) {
    const empresaId = await empresaIdAutenticada(req);
    const actor = await extraerActorAuditoriaConNombre(req);
    if (!actor) throw Object.assign(new Error("No autenticado"), { status: 401 });
    return new InventarioActivoService(prisma, empresaId, actor);
  }

  catalogoMaquinaria: RequestHandler = async (req, res, next) => {
    try {
      res.json(await (await this.service(req)).listarCatalogoMaquinaria(String(req.query.q ?? "")));
    } catch (error) { next(error); }
  };

  catalogoHerramientas: RequestHandler = async (req, res, next) => {
    try {
      res.json(await (await this.service(req)).listarCatalogoHerramientas(String(req.query.q ?? "")));
    } catch (error) { next(error); }
  };

  resumenEmpresa: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).resumen()); } catch (error) { next(error); }
  };

  resumenConjunto: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).resumen(String(req.params.nit))); } catch (error) { next(error); }
  };

  listarMaquinariaEmpresa: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).listarMaquinaria(ListaMaquinariaQuery.parse(req.query))); } catch (error) { next(error); }
  };

  listarMaquinariaConjunto: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).listarMaquinaria(ListaMaquinariaQuery.parse(req.query), String(req.params.nit))); } catch (error) { next(error); }
  };

  crearMaquinariaEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const dto = CrearMaquinariaInventarioBody.parse(req.body);
      res.status(201).json(await (await this.service(req)).crearMaquinaria(dto, { propietarioTipo: PropietarioMaquinaria.EMPRESA, conjuntoId: null }));
    } catch (error) { next(error); }
  };

  crearMaquinariaConjunto: RequestHandler = async (req, res, next) => {
    try {
      const dto = CrearMaquinariaInventarioBody.parse(req.body);
      res.status(201).json(await (await this.service(req)).crearMaquinaria(dto, { propietarioTipo: PropietarioMaquinaria.CONJUNTO, conjuntoId: String(req.params.nit) }));
    } catch (error) { next(error); }
  };

  listarHerramientasEmpresa: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).listarHerramientas(ListaHerramientasQuery.parse(req.query))); } catch (error) { next(error); }
  };

  listarHerramientasConjunto: RequestHandler = async (req, res, next) => {
    try { res.json(await (await this.service(req)).listarHerramientas(ListaHerramientasQuery.parse(req.query), String(req.params.nit))); } catch (error) { next(error); }
  };

  crearHerramientasEmpresa: RequestHandler = async (req, res, next) => {
    try {
      const dto = CrearHerramientasInventarioBody.parse(req.body);
      res.status(201).json(await (await this.service(req)).crearHerramientas(dto, { propietarioTipo: PropietarioMaquinaria.EMPRESA, conjuntoId: null }));
    } catch (error) { next(error); }
  };

  crearHerramientasConjunto: RequestHandler = async (req, res, next) => {
    try {
      const dto = CrearHerramientasInventarioBody.parse(req.body);
      res.status(201).json(await (await this.service(req)).crearHerramientas(dto, { propietarioTipo: PropietarioMaquinaria.CONJUNTO, conjuntoId: String(req.params.nit) }));
    } catch (error) { next(error); }
  };

  editar = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      res.json(await (await this.service(req)).editar(kind, id, EditarActivoBody.parse(req.body)));
    } catch (error) { next(error); }
  };

  aprobar = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      const body = AprobarActivoBody.parse(req.body ?? {});
      res.json(await (await this.service(req)).aprobar(kind, id, body.catalogoDestinoId));
    } catch (error) { next(error); }
  };

  aprobarLoteHerramientas: RequestHandler = async (req, res, next) => {
    try {
      const { loteId } = LoteActivoParam.parse(req.params);
      res.json(await (await this.service(req)).aprobarLoteHerramientas(loteId));
    } catch (error) { next(error); }
  };

  rechazarLoteHerramientas: RequestHandler = async (req, res, next) => {
    try {
      const { loteId } = LoteActivoParam.parse(req.params);
      const body = RechazarActivoBody.parse(req.body);
      res.json(
        await (await this.service(req)).rechazarLoteHerramientas(
          loteId,
          body.motivo,
        ),
      );
    } catch (error) { next(error); }
  };

  rechazar = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      const body = RechazarActivoBody.parse(req.body);
      res.json(await (await this.service(req)).rechazar(kind, id, body.motivo));
    } catch (error) { next(error); }
  };

  cambiarEstado = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      const body = kind === "maquinaria" ? CambiarEstadoMaquinariaBody.parse(req.body) : CambiarEstadoHerramientaBody.parse(req.body);
      res.json(await (await this.service(req)).cambiarEstado(kind, id, body.estado, body.motivo));
    } catch (error) { next(error); }
  };

  prestar = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      res.status(201).json(await (await this.service(req)).prestar(kind, id, PrestarActivoBody.parse(req.body)));
    } catch (error) { next(error); }
  };

  devolver = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      res.json(await (await this.service(req)).devolver(kind, id));
    } catch (error) { next(error); }
  };

  obtenerFoto = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      const photo = await (await this.service(req)).obtenerFoto(kind, id);
      res.setHeader("Content-Type", photo.mimeType);
      res.setHeader("Cache-Control", "private, no-store");
      photo.stream.on("error", next);
      photo.stream.pipe(res);
    } catch (error) { next(error); }
  };

  guardarFoto = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      if (!req.file) throw Object.assign(new Error("Debes adjuntar una fotografía."), { status: 400 });
      res.json(await (await this.service(req)).guardarFoto(kind, id, req.file));
    } catch (error) {
      if (req.file?.path) {
        await fs.promises.unlink(req.file.path).catch(() => undefined);
      }
      next(error);
    }
  };

  eliminarFoto = (kind: Kind): RequestHandler => async (req, res, next) => {
    try {
      const { id } = IdActivoParam.parse(req.params);
      await (await this.service(req)).eliminarFoto(kind, id);
      res.status(204).send();
    } catch (error) { next(error); }
  };
}
