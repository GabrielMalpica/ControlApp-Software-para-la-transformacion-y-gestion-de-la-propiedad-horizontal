import { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { z } from "zod";
import { SolicitudHerramientaService } from "../services/SolicitudHerramientaService";
import {
  CrearSolicitudHerramientaBody,
} from "../model/Herramienta";

const SolicitudIdParam = z.object({
  solicitudId: z.coerce.number().int().positive(),
});

export class SolicitudHerramientaController {

  // POST /solicitudes-herramientas
  crear: RequestHandler = async (req, res, next) => {
    try {
      const body = CrearSolicitudHerramientaBody.parse(req.body);
      const service = new SolicitudHerramientaService(prisma);
      const out = await service.crear(body);
      res.status(201).json(out);
    } catch (err: any) {
      if (err?.code === "P2003") {
        (err as any).status = 409;
        (err as any).message = "Conjunto/Empresa/Herramienta no existe.";
      }
      next(err);
    }
  };

  // GET /solicitudes-herramientas?conjuntoId=&empresaId=&estado=
  listar: RequestHandler = async (req, res, next) => {
    try {
      const conjuntoId = req.query.conjuntoId
        ? String(req.query.conjuntoId)
        : undefined;
      const empresaId = req.query.empresaId
        ? String(req.query.empresaId)
        : undefined;
      const estado = req.query.estado
        ? (String(req.query.estado) as any)
        : undefined;

      const service = new SolicitudHerramientaService(prisma);
      const out = await service.listar({ conjuntoId, empresaId, estado });
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // GET /solicitudes-herramientas/:solicitudId
  obtener: RequestHandler = async (req, res, next) => {
    try {
      const { solicitudId } = SolicitudIdParam.parse(req.params);
      const service = new SolicitudHerramientaService(prisma);
      const out = await service.obtener(solicitudId);
      res.json(out);
    } catch (err) {
      next(err);
    }
  };

  // PATCH /solicitudes-herramientas/:solicitudId/estado
  // cambiarEstado: RequestHandler = async (req, res, next) => {
  //   try {
  //     const { solicitudId } = SolicitudIdParam.parse(req.params);
  //     const body = CambiarEstadoSolicitudBody.parse(req.body);

  //     const service = new SolicitudHerramientaService(prisma);
  //     const out = await service.cambiarEstado(solicitudId, {
  //       estado: body.estado,
  //       observacionRespuesta: body.observacionRespuesta ?? null,
  //     });

  //     res.json(out);
  //   } catch (err) {
  //     next(err);
  //   }
  // };
}
