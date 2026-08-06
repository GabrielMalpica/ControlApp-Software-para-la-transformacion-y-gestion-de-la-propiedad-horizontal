import type { RequestHandler } from "express";
import { prisma } from "../db/prisma";
import { PedidoDetalleParamDTO, PedidoItemParamDTO } from "../model/Commerce";
import { CommerceLifecycleService } from "../services/CommerceLifecycleService";

const service = new CommerceLifecycleService(prisma);

export class CommerceLifecycleController {
  obtenerPedido: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { pedidoId } = PedidoDetalleParamDTO.parse(req.params);
      res.json(await service.getPedido(req.user.sub, pedidoId));
    } catch (error) {
      next(error);
    }
  };

  cambiarEstado: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { pedidoId } = PedidoDetalleParamDTO.parse(req.params);
      res.json(await service.transicionar(req.user.sub, pedidoId, req.body));
    } catch (error) {
      next(error);
    }
  };

  vistaPreviaRecepcion: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { pedidoId } = PedidoDetalleParamDTO.parse(req.params);
      res.json(await service.previewRecepcion(req.user.sub, pedidoId));
    } catch (error) {
      next(error);
    }
  };

  mapearItem: RequestHandler = async (req, res, next) => {
    try {
      if (!req.user?.sub) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { pedidoId, itemId } = PedidoItemParamDTO.parse(req.params);
      res.json(await service.mapearItem(req.user.sub, pedidoId, itemId, req.body));
    } catch (error) {
      next(error);
    }
  };
}
