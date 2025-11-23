import { Request, Response } from "express";
import { PrismaClient, Prisma } from "../generated/prisma";
import {
  CrearInsumoDTO,
  EditarInsumoDTO,
  FiltroInsumoDTO,
  insumoPublicSelect,
  toInsumoPublico,
} from "../model/Insumo";

export const asyncHandler =
  (fn: (req: Request, res: Response) => Promise<any>) =>
  (req: Request, res: Response) =>
    fn(req, res).catch((err) => {
      console.error(err);
      res.status(400).json({ error: err?.message ?? "Error inesperado" });
    });

export class InsumoController {
  constructor(private prisma: PrismaClient) {}

  /** POST /insumos  (catalogo corporativo: empresaId = null) */
  crear = async (req: Request, res: Response) => {
    const dto = CrearInsumoDTO.parse(req.body);

    const empresaId: string | null = null; // si no separas por empresa

    const existe = await this.prisma.insumo.findFirst({
      where: {
        empresaId,
        nombre: dto.nombre,
        unidad: dto.unidad,
      },
      select: { id: true },
    });
    if (existe) throw new Error("Ya existe un insumo con ese nombre y unidad.");

    const creado = await this.prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId,
        categoria: dto.categoria,
        umbralBajo: dto.umbralBajo ?? null,
      },
      select: insumoPublicSelect,
    });

    res.status(201).json(toInsumoPublico(creado));
  };

  /** PATCH /insumos/:id */
  actualizar = async (req: Request, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const dto = EditarInsumoDTO.parse(req.body);

    const data: Prisma.InsumoUpdateInput = {
      nombre: dto.nombre ?? undefined,
      unidad: dto.unidad ?? undefined,
      empresa: dto.empresaId
        ? { connect: { nit: dto.empresaId } }
        : dto.empresaId === null
        ? { disconnect: true }
        : undefined,
      categoria: dto.categoria ?? undefined,
      umbralBajo:
        dto.umbralBajo === undefined
          ? undefined
          : dto.umbralBajo === null
          ? null
          : dto.umbralBajo,
    };

    const actualizado = await this.prisma.insumo.update({
      where: { id },
      data,
      select: insumoPublicSelect,
    });

    res.json(toInsumoPublico(actualizado));
  };

  /** GET /insumos */
  listar = async (req: Request, res: Response) => {
    const f = FiltroInsumoDTO.parse(req.query);

    const where: Prisma.InsumoWhereInput = {
      empresaId: f.empresaId ?? null, // corporativo
      nombre: f.nombre ? { contains: f.nombre, mode: "insensitive" } : undefined,
      categoria: f.categoria ?? undefined,
    };

    const items = await this.prisma.insumo.findMany({
      where,
      orderBy: { nombre: "asc" },
      select: insumoPublicSelect,
    });

    res.json(items.map(toInsumoPublico));
  };

  /** GET /insumos/:id */
  obtener = async (req: Request, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    const item = await this.prisma.insumo.findUnique({
      where: { id },
      select: insumoPublicSelect,
    });
    if (!item) return res.status(404).json({ error: "No encontrado" });

    res.json(toInsumoPublico(item));
  };

  /** DELETE /insumos/:id */
  eliminar = async (req: Request, res: Response) => {
    const id = Number(req.params.id);
    if (!Number.isFinite(id)) throw new Error("ID inválido");

    await this.prisma.insumo.delete({ where: { id } });
    res.status(204).send();
  };
}
