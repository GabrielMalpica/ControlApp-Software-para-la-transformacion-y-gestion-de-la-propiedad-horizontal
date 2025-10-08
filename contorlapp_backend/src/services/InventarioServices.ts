import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

const AgregarInsumoDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});

const InsumoIdDTO = z.object({
  insumoId: z.number().int().positive(),
});

const UmbralDTO = z.object({
  umbral: z.number().int().min(0).default(5),
});

export class InventarioService {
  constructor(private prisma: PrismaClient, private inventarioId: number) {}

  async agregarInsumo(payload: unknown) {
    const { insumoId, cantidad } = AgregarInsumoDTO.parse(payload);

    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      select: { id: true },
    });

    if (existente) {
      return this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { increment: cantidad } },
      });
    }
    return this.prisma.inventarioInsumo.create({
      data: { inventarioId: this.inventarioId, insumoId, cantidad },
    });
  }

  async listarInsumos(): Promise<string[]> {
    const insumos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true },
    });
    return insumos.map((i) => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`);
  }

  async eliminarInsumo(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);
    await this.prisma.inventarioInsumo.deleteMany({
      where: { inventarioId: this.inventarioId, insumoId },
    });
  }

  async buscarInsumoPorId(payload: unknown) {
    const { insumoId } = InsumoIdDTO.parse(payload);
    return this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true },
    });
  }

  async consumirInsumoPorId(payload: unknown) {
    const { insumoId, cantidad } = AgregarInsumoDTO.parse(payload); // mismas reglas

    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true },
    });

    if (!existente) throw new Error(`El insumo con ID "${insumoId}" no existe en el inventario.`);
    if (existente.cantidad < cantidad) {
      throw new Error(`Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${existente.cantidad}`);
    }

    await this.prisma.inventarioInsumo.update({
      where: { id: existente.id },
      data: { cantidad: { decrement: cantidad } },
    });

    await this.prisma.consumoInsumo.create({
      data: {
        inventarioId: this.inventarioId,
        insumoId,
        cantidad,
        fecha: new Date(),
      },
    });
  }

  async listarInsumosBajos(payload?: unknown): Promise<string[]> {
    const { umbral } = UmbralDTO.parse(payload ?? {});
    const bajos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId, cantidad: { lte: umbral } },
      include: { insumo: true },
    });

    return bajos.map(
      (i) => `⚠️ ${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad} (bajo stock)`
    );
  }
}
