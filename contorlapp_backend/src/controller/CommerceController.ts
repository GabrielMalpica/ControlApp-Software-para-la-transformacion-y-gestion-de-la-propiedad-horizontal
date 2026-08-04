import { RequestHandler } from "express";
import { z } from "zod";
import { WooCommerceCatalogService } from "../services/WooCommerceCatalogService";

const ListCatalogQuery = z.object({
  q: z.string().trim().optional(),
  target: z.enum(["todos", "residente", "conjunto", "servicios"]).optional(),
  category: z.string().trim().optional(),
  page: z.coerce.number().int().min(1).optional(),
  perPage: z.coerce.number().int().min(1).max(100).optional(),
});

const ProductIdParam = z.object({
  productId: z.coerce.number().int().positive(),
});

const service = new WooCommerceCatalogService();

export class CommerceController {
  listarCatalogo: RequestHandler = async (req, res, next) => {
    try {
      const query = ListCatalogQuery.parse(req.query);
      const data = await service.listCatalog(query);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };

  obtenerProducto: RequestHandler = async (req, res, next) => {
    try {
      const { productId } = ProductIdParam.parse(req.params);
      const data = await service.getProduct(productId);
      res.json(data);
    } catch (error) {
      next(error);
    }
  };
}
