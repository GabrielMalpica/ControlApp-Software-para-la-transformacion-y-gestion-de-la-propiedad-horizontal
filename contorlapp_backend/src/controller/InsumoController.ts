import { Request, Response } from "express";
import { prisma } from "../db/prisma";
import {
  CrearInsumoDTO,
  FiltroInsumoDTO,
  insumoPublicSelect,
  toInsumoPublico,
} from "../model/Insumo_tmp";

const EMPRESA_CORPORATIVA = "CORPORATIVO";

export class InsumoController {
  crear = async (req: Request, res: Response) => {
    const dto = CrearInsumoDTO.parse(req.body);

    const empresaId = dto.empresaId ?? EMPRESA_CORPORATIVA;

    const existe = await prisma.insumo.findFirst({
      where: {
        empresaId,
        nombre: dto.nombre,
        unidad: dto.unidad,
      },
      select: { id: true },
    });

    if (existe) throw new Error("Ya existe un insumo con ese nombre y unidad.");

    const creado = await prisma.insumo.create({
      data: {
        nombre: dto.nombre,
        unidad: dto.unidad,
        empresaId,
        categoria: dto.categoria,
        umbralBajo: dto.umbralBajo ?? undefined,
      },
      select: insumoPublicSelect,
    });

    res.status(201).json(toInsumoPublico(creado));
  };

  listar = async (req: Request, res: Response) => {
    const f = FiltroInsumoDTO.parse(req.query);

    const where = {
      empresaId: (f.empresaId ?? EMPRESA_CORPORATIVA),
      nombre: f.nombre ? { contains: f.nombre, mode: "insensitive" as const } : undefined,
      categoria: f.categoria ?? undefined,
    };

    const items = await prisma.insumo.findMany({
      where,
      orderBy: { nombre: "asc" },
      select: insumoPublicSelect,
    });

    res.json(items.map(toInsumoPublico));
  };
}
