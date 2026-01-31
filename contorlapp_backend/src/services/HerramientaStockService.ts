import { PrismaClient } from "../generated/prisma";

type EstadoStock = "OPERATIVA" | "DANADA" | "PERDIDA" | "BAJA";

export class HerramientaStockService {
  constructor(private prisma: PrismaClient, private conjuntoId: string) {}

  async listarStock({ estado }: { estado?: EstadoStock } = {}) {
    return this.prisma.conjuntoHerramientaStock.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        ...(estado ? { estado } : {}),
      },
      include: { herramienta: true },
      orderBy: { herramienta: { nombre: "asc" } },
    });
  }

  async upsertStock(data: {
    herramientaId: number;
    cantidad: number;
    estado: EstadoStock;
  }) {
    return this.prisma.conjuntoHerramientaStock.upsert({
      where: {
        conjuntoId_herramientaId_estado: {
          conjuntoId: this.conjuntoId,
          herramientaId: data.herramientaId,
          estado: data.estado,
        },
      },
      create: {
        conjuntoId: this.conjuntoId,
        herramientaId: data.herramientaId,
        cantidad: data.cantidad as any,
        estado: data.estado as any,
      },
      update: {
        cantidad: data.cantidad as any,
      },
      include: { herramienta: true },
    });
  }

  async ajustarStock(data: {
    herramientaId: number;
    delta: number;
    estado: EstadoStock;
  }) {
    return this.prisma.$transaction(async (tx) => {
      const row = await tx.conjuntoHerramientaStock.findUnique({
        where: {
          conjuntoId_herramientaId_estado: {
            conjuntoId: this.conjuntoId,
            herramientaId: data.herramientaId,
            estado: data.estado,
          },
        },
      });

      if (!row) {
        const e: any = new Error(
          "No existe stock para esa herramienta/estado en este conjunto"
        );
        e.status = 404;
        throw e;
      }

      const nuevaCantidad = Number(row.cantidad) + Number(data.delta);
      if (nuevaCantidad < 0) {
        const e: any = new Error("Stock insuficiente");
        e.status = 409;
        throw e;
      }

      return tx.conjuntoHerramientaStock.update({
        where: {
          conjuntoId_herramientaId_estado: {
            conjuntoId: this.conjuntoId,
            herramientaId: data.herramientaId,
            estado: data.estado,
          },
        },
        data: { cantidad: nuevaCantidad as any },
        include: { herramienta: true },
      });
    });
  }

  async eliminarStock(data: { herramientaId: number; estado: EstadoStock }) {
    return this.prisma.conjuntoHerramientaStock.delete({
      where: {
        conjuntoId_herramientaId_estado: {
          conjuntoId: this.conjuntoId,
          herramientaId: data.herramientaId,
          estado: data.estado,
        },
      },
    });
  }
}
