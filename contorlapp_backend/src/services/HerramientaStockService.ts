import { PrismaClient } from "@prisma/client";

type EstadoStock = "OPERATIVA" | "DANADA" | "PERDIDA" | "BAJA";
type OrigenStock = "EMPRESA" | "CONJUNTO";

export class HerramientaStockService {
  constructor(private prisma: PrismaClient, private conjuntoId: string) {}

  async listarStockEmpresa(empresaId: string) {
    return (this.prisma as any).empresaHerramientaStock.findMany({
      where: { empresaId },
      include: { herramienta: true },
      orderBy: { herramienta: { nombre: "asc" } },
    });
  }

  async upsertStockEmpresa(data: { empresaId: string; herramientaId: number; cantidad: number }) {
    return (this.prisma as any).empresaHerramientaStock.upsert({
      where: {
        empresaId_herramientaId: {
          empresaId: data.empresaId,
          herramientaId: data.herramientaId,
        },
      },
      create: {
        empresaId: data.empresaId,
        herramientaId: data.herramientaId,
        cantidad: data.cantidad as any,
      },
      update: {
        cantidad: data.cantidad as any,
      },
      include: { herramienta: true },
    });
  }

  async ajustarStockEmpresa(data: { empresaId: string; herramientaId: number; delta: number }) {
    return this.prisma.$transaction(async (tx) => {
      const row = await (tx as any).empresaHerramientaStock.findUnique({
        where: {
          empresaId_herramientaId: {
            empresaId: data.empresaId,
            herramientaId: data.herramientaId,
          },
        },
      });

      if (!row) {
        const e: any = new Error("No existe stock de empresa para esa herramienta");
        e.status = 404;
        throw e;
      }

      const nuevaCantidad = Number(row.cantidad) + Number(data.delta);
      if (nuevaCantidad < 0) {
        const e: any = new Error("Stock de empresa insuficiente");
        e.status = 409;
        throw e;
      }

      return (tx as any).empresaHerramientaStock.update({
        where: {
          empresaId_herramientaId: {
            empresaId: data.empresaId,
            herramientaId: data.herramientaId,
          },
        },
        data: { cantidad: nuevaCantidad as any },
        include: { herramienta: true },
      });
    });
  }

  async eliminarStockEmpresa(data: { empresaId: string; herramientaId: number }) {
    return (this.prisma as any).empresaHerramientaStock.delete({
      where: {
        empresaId_herramientaId: {
          empresaId: data.empresaId,
          herramientaId: data.herramientaId,
        },
      },
    });
  }

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

  async listarDisponibilidad(params: {
    empresaId: string;
    fechaInicio?: Date;
    fechaFin?: Date;
    excluirTareaId?: number;
  }) {
    const { empresaId, fechaInicio, fechaFin, excluirTareaId } = params;

    const [catalogo, stockConjunto, stockEmpresa, reservas] = await Promise.all([
      this.prisma.herramienta.findMany({
        where: { empresaId },
        orderBy: { nombre: "asc" },
      }),
      this.prisma.conjuntoHerramientaStock.findMany({
        where: { conjuntoId: this.conjuntoId, estado: "OPERATIVA" },
        select: { herramientaId: true, cantidad: true },
      }),
      (this.prisma as any).empresaHerramientaStock.findMany({
        where: { empresaId },
        select: { herramientaId: true, cantidad: true },
      }),
      fechaInicio && fechaFin
        ? (this.prisma.usoHerramienta as any).findMany({
            where: {
              fechaInicio: { lt: fechaFin },
              OR: [{ fechaFin: null }, { fechaFin: { gt: fechaInicio } }],
              estado: { in: ["RESERVADA", "EN_USO"] as any },
              ...(excluirTareaId ? { tareaId: { not: excluirTareaId } } : {}),
              tarea: {
                estado: {
                  notIn: [
                    "COMPLETADA",
                    "NO_COMPLETADA",
                    "CANCELADA",
                  ] as any,
                },
              },
            },
            select: {
              herramientaId: true,
              cantidad: true,
              origenStock: true,
            },
          })
        : Promise.resolve([]),
    ]);

    const conjuntoMap = new Map(stockConjunto.map((r) => [r.herramientaId, Number(r.cantidad)]));
    const empresaMap = new Map(stockEmpresa.map((r) => [r.herramientaId, Number(r.cantidad)]));
    const reservadas = new Map<string, number>();

    for (const r of reservas) {
      const key = `${r.herramientaId}:${r.origenStock as OrigenStock}`;
      reservadas.set(key, (reservadas.get(key) ?? 0) + Number(r.cantidad));
    }

    return catalogo.map((h) => {
      const stockConjuntoTotal = Number(conjuntoMap.get(h.id) ?? 0);
      const stockEmpresaTotal = Number(empresaMap.get(h.id) ?? 0);
      const reservadoConjunto = Number(reservadas.get(`${h.id}:CONJUNTO`) ?? 0);
      const reservadoEmpresa = Number(reservadas.get(`${h.id}:EMPRESA`) ?? 0);
      const disponibleConjunto = Math.max(0, stockConjuntoTotal - reservadoConjunto);
      const disponibleEmpresa = Math.max(0, stockEmpresaTotal - reservadoEmpresa);

      return {
        herramientaId: h.id,
        nombre: h.nombre,
        unidad: h.unidad,
        categoria: (h as any).categoria ?? "OTROS",
        modoControl: h.modoControl,
        umbralBajo: h.umbralBajo,
        stockConjunto: stockConjuntoTotal,
        stockEmpresa: stockEmpresaTotal,
        reservadoConjunto,
        reservadoEmpresa,
        disponibleConjunto,
        disponibleEmpresa,
        totalDisponible: disponibleConjunto + disponibleEmpresa,
      };
    });
  }
}
