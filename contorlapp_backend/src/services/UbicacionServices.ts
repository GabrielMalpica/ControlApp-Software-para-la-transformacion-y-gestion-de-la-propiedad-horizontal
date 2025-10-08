import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

const NombreDTO = z.object({ nombre: z.string().min(1) });

export class UbicacionService {
  constructor(private prisma: PrismaClient, private ubicacionId: number) {}

  async agregarElemento(payload: unknown): Promise<void> {
    const { nombre } = NombreDTO.parse(payload);
    await this.prisma.elemento.create({
      data: {
        nombre,
        ubicacion: { connect: { id: this.ubicacionId } },
      },
    });
  }

  async listarElementos(): Promise<string[]> {
    const elementos = await this.prisma.elemento.findMany({
      where: { ubicacionId: this.ubicacionId },
      select: { nombre: true },
    });
    return elementos.map((e) => e.nombre);
  }

  async buscarElementoPorNombre(payload: unknown): Promise<{ id: number; nombre: string } | null> {
    const { nombre } = NombreDTO.parse(payload);
    return this.prisma.elemento.findFirst({
      where: {
        ubicacionId: this.ubicacionId,
        nombre: { equals: nombre, mode: "insensitive" },
      },
      select: { id: true, nombre: true },
    });
  }
}
