import { PrismaClient } from '../generated/prisma';

export class InventarioService {
  constructor(private prisma: PrismaClient, private inventarioId: number) {}

  async agregarInsumo(insumoId: number, cantidad: number) {
    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId }
    });

    if (existente) {
      return await this.prisma.inventarioInsumo.update({
        where: { id: existente.id },
        data: { cantidad: { increment: cantidad } }
      });
    } else {
      return await this.prisma.inventarioInsumo.create({
        data: {
          inventarioId: this.inventarioId,
          insumoId,
          cantidad
        }
      });
    }
  }

  async listarInsumos(): Promise<string[]> {
    const insumos = await this.prisma.inventarioInsumo.findMany({
      where: { inventarioId: this.inventarioId },
      include: { insumo: true }
    });

    return insumos.map(i => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`);
  }

  async eliminarInsumo(insumoId: number) {
    await this.prisma.inventarioInsumo.deleteMany({
      where: { inventarioId: this.inventarioId, insumoId }
    });
  }

  async buscarInsumoPorId(insumoId: number) {
    return await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true }
    });
  }

  async consumirInsumoPorId(insumoId: number, cantidad: number) {
    const existente = await this.prisma.inventarioInsumo.findFirst({
      where: { inventarioId: this.inventarioId, insumoId },
      include: { insumo: true }
    });

    if (!existente) throw new Error(`El insumo con ID "${insumoId}" no existe en el inventario.`);
    if (existente.cantidad < cantidad) {
      throw new Error(`Cantidad insuficiente de "${existente.insumo.nombre}". Disponible: ${existente.cantidad}`);
    }

    await this.prisma.inventarioInsumo.update({
      where: { id: existente.id },
      data: { cantidad: { decrement: cantidad } }
    });

    await this.prisma.consumoInsumo.create({
      data: {
        inventarioId: this.inventarioId,
        insumoId,
        cantidad,
        fecha: new Date()
      }
    });
  }

  async listarInsumosBajos(umbral: number = 5): Promise<string[]> {
    const bajos = await this.prisma.inventarioInsumo.findMany({
      where: {
        inventarioId: this.inventarioId,
        cantidad: { lte: umbral }
      },
      include: { insumo: true }
    });

    return bajos.map(i => `⚠️ ${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad} (bajo stock)`);
  }
}
