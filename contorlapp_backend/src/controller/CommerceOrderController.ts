import { RequestHandler } from "express";
import { PedidoDetalleParamDTO } from "../model/Commerce";
import { prisma } from "../db/prisma";
import { CommerceOrderService } from "../services/CommerceOrderService";

const service = new CommerceOrderService(prisma);

export class CommerceOrderController {
  crearPedidoConjunto: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const data = await service.createConjuntoOrder(userId, req.body);
      res.status(201).json(data);
    } catch (error) {
      next(error);
    }
  };

  listarPedidosConjunto: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const data = await service.listConjuntoOrders(userId);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };

  obtenerPedidoConjunto: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const { pedidoId } = PedidoDetalleParamDTO.parse(req.params);
      const data = await service.getConjuntoOrder(userId, pedidoId);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };

  crearPedidoResidente: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const data = await service.createResidentOrder(userId, req.body);
      res.status(201).json(data);
    } catch (error) {
      next(error);
    }
  };

  listarPedidosResidente: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }

      const data = await service.listResidentOrders(userId);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };

  obtenerPedidoResidente: RequestHandler = async (req, res, next) => {
    try {
      const userId = req.user?.sub;
      if (!userId) {
        res.status(401).json({ message: "No autenticado" });
        return;
      }
      const { pedidoId } = PedidoDetalleParamDTO.parse(req.params);
      const data = await service.getResidentOrder(userId, pedidoId);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };
}
