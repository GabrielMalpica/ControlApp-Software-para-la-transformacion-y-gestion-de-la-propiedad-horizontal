import { Request, Response } from "express";
import { PrismaClient } from "../generated/prisma";
import { DefinicionTareaPreventivaService } from "../services/DefinicionTareaPreventivaService";
import {
  CrearDefinicionPreventivaDTO,
  EditarDefinicionPreventivaDTO,
  GenerarCronogramaDTO,
} from "../model/DefinicionTareaPreventiva";

export const asyncHandler =
  (fn: (req: Request, res: Response) => Promise<any>) =>
  (req: Request, res: Response) =>
    fn(req, res).catch((err) => {
      console.error(err);
      res.status(400).json({ error: err?.message ?? "Error inesperado" });
    });

export class DefinicionTareaPreventivaController {
  constructor(private prisma: PrismaClient) {}

  /** POST /conjuntos/:nit/preventivas */
  crear = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const dto = CrearDefinicionPreventivaDTO.parse({
      ...req.body,
      conjuntoId,
    });

    const svc = new DefinicionTareaPreventivaService(this.prisma);
    const def = await svc.crear(dto);
    res.status(201).json(def);
  };

  /** GET /conjuntos/:nit/preventivas */
  listar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const svc = new DefinicionTareaPreventivaService(this.prisma);
    const defs = await svc.listarPorConjunto(conjuntoId);
    res.json(defs);
  };

  /** PATCH /conjuntos/:nit/preventivas/:id */
  actualizar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const dto = EditarDefinicionPreventivaDTO.parse(req.body);
    const svc = new DefinicionTareaPreventivaService(this.prisma);
    const def = await svc.actualizar(conjuntoId, id, dto);
    res.json(def);
  };

  /** DELETE /conjuntos/:nit/preventivas/:id */
  eliminar = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const svc = new DefinicionTareaPreventivaService(this.prisma);
    await svc.eliminar(conjuntoId, id);
    res.status(204).send();
  };

  /** POST /conjuntos/:nit/preventivas/generar-cronograma */
  generarCronogramaMensual = async (req: Request, res: Response) => {
    const conjuntoId = req.params.nit;
    const dto = GenerarCronogramaDTO.parse({
      ...req.body,
      conjuntoId,
    });

    const svc = new DefinicionTareaPreventivaService(this.prisma);
    const resultado = await svc.generarCronograma(dto);
    res.status(201).json(resultado);
  };
}
