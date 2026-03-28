import type{ PrismaClient } from "@prisma/client";

export class HerramientaService {
  constructor(private prisma: PrismaClient) {}

  async crear(data: {
    empresaId: string;
    nombre: string;
    unidad: string;
    categoria: "LIMPIEZA" | "JARDINERIA" | "PISCINA" | "OTROS";
    modoControl: "PRESTAMO" | "CONSUMO" | "VIDA_CORTA";
    vidaUtilDias?: number | null;
    umbralBajo?: number | null;
  }) {
    return this.prisma.$transaction(async (tx) => {
      const creada = await tx.herramienta.create({
        data: {
          empresaId: data.empresaId,
          nombre: data.nombre.trim(),
          unidad: data.unidad.trim(),
          categoria: data.categoria,
          modoControl: data.modoControl,
          vidaUtilDias: data.vidaUtilDias ?? null,
          umbralBajo: data.umbralBajo ?? null,
        } as any,
      });

      await (tx as any).empresaHerramientaStock.upsert({
        where: {
          empresaId_herramientaId: {
            empresaId: data.empresaId,
            herramientaId: creada.id,
          },
        },
        create: {
          empresaId: data.empresaId,
          herramientaId: creada.id,
          cantidad: 0 as any,
        },
        update: {},
      });

      return creada;
    });
  }

  async listar(params: {
    empresaId: string;
    nombre?: string;
    take: number;
    skip: number;
  }) {
    const where: any = { empresaId: params.empresaId };

    if (params.nombre?.trim()) {
      where.nombre = { contains: params.nombre.trim(), mode: "insensitive" };
    }

    const [total, data] = await Promise.all([
      this.prisma.herramienta.count({ where }),
      this.prisma.herramienta.findMany({
        where,
        orderBy: { nombre: "asc" },
        include: {
          stocksEmpresa: {
            where: { empresaId: params.empresaId },
            select: { cantidad: true },
            take: 1,
          },
        } as any,
        take: params.take,
        skip: params.skip,
      }),
    ]);

    return {
      total,
      data: (data as any[]).map((item) => ({
        ...item,
        stockEmpresa:
          item.stocksEmpresa.length > 0 ? Number(item.stocksEmpresa[0].cantidad) : 0,
      })),
    };
  }

  async obtenerPorId(herramientaId: number) {
    const h = await this.prisma.herramienta.findUnique({
      where: { id: herramientaId },
    });
    if (!h) {
      const e: any = new Error("Herramienta no encontrada");
      e.status = 404;
      throw e;
    }
    return h;
  }

  async editar(
    herramientaId: number,
    data: Partial<{
      nombre: string;
      unidad: string;
      categoria: "LIMPIEZA" | "JARDINERIA" | "PISCINA" | "OTROS";
      modoControl: "PRESTAMO" | "CONSUMO" | "VIDA_CORTA";
      vidaUtilDias: number | null;
      umbralBajo: number | null;
    }>
  ) {
    await this.obtenerPorId(herramientaId);

    return this.prisma.herramienta.update({
      where: { id: herramientaId },
      data: {
        ...(data.nombre !== undefined ? { nombre: data.nombre.trim() } : {}),
        ...(data.unidad !== undefined ? { unidad: data.unidad.trim() } : {}),
        ...(data.categoria !== undefined ? { categoria: data.categoria } : {}),
        ...(data.modoControl !== undefined
          ? { modoControl: data.modoControl }
          : {}),
        ...(data.vidaUtilDias !== undefined
          ? { vidaUtilDias: data.vidaUtilDias }
          : {}),
        ...(data.umbralBajo !== undefined
          ? { umbralBajo: data.umbralBajo }
          : {}),
      } as any,
    });
  }

  async eliminar(herramientaId: number) {
    await this.obtenerPorId(herramientaId);
    return this.prisma.herramienta.delete({ where: { id: herramientaId } });
  }
}
