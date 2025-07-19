import { PrismaClient } from '../generated/prisma';

export class UbicacionService {
  constructor(private prisma: PrismaClient, private ubicacionId: number) {}

  async agregarElemento(nombre: string): Promise<void> {
    await this.prisma.elemento.create({
      data: {
        nombre,
        ubicacion: {
          connect: { id: this.ubicacionId },
        },
      },
    });
  }

  async listarElementos(): Promise<string[]> {
    const elementos = await this.prisma.elemento.findMany({
      where: { ubicacionId: this.ubicacionId },
      select: { nombre: true },
    });

    return elementos.map(e => e.nombre);
  }

  async buscarElementoPorNombre(nombre: string): Promise<{ id: number; nombre: string } | null> {
    return await this.prisma.elemento.findFirst({
      where: {
        ubicacionId: this.ubicacionId,
        nombre: {
          equals: nombre,
          mode: "insensitive",
        },
      },
      select: {
        id: true,
        nombre: true,
      },
    });
  }
}
