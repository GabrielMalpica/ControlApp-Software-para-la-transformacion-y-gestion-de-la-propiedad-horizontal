import type { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { CommercePointsService } from "../services/CommercePointsService";

const service = new CommercePointsService(prisma);

export class CommercePointsController {
  obtenerResumen: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      res.json(await service.getResumen(req.user.sub, req.query));
    } catch (error) {
      next(error);
    }
  };

  obtenerConfiguracion: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      res.json(await service.getConfiguracion(req.user.sub, req.query));
    } catch (error) {
      next(error);
    }
  };

  configurar: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      res.json(await service.configurar(req.user.sub, req.body));
    } catch (error) {
      next(error);
    }
  };

  redimir: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      res.status(201).json(await service.redimir(req.user.sub, req.body));
    } catch (error) {
      next(error);
    }
  };

  ajustar: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      res.status(201).json(await service.ajustar(req.user.sub, req.body));
    } catch (error) {
      next(error);
    }
  };
}
