import { PrismaClient, EstadoTarea } from '../generated/prisma';

export class ReporteService {
  constructor(private prisma: PrismaClient) {}

  async tareasAprobadasPorFecha(desde: Date, hasta: Date) {
    return await this.prisma.tarea.findMany({
      where: {
        estado: "APROBADA",
        fechaVerificacion: {
          gte: desde,
          lte: hasta,
        },
      },
      include: {
        ubicacion: true,
        elemento: true,
        operario: true,
      },
    });
  }

  async tareasRechazadasPorFecha(desde: Date, hasta: Date) {
    return await this.prisma.tarea.findMany({
      where: {
        estado: "RECHAZADA",
        fechaVerificacion: {
          gte: desde,
          lte: hasta,
        },
      },
      include: {
        ubicacion: true,
        elemento: true,
        operario: true,
      },
    });
  }

  async usoDeInsumosPorFecha(conjuntoId: number, desde: Date, hasta: Date) {
    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId },
      include: {
        consumos: {
          where: {
            fecha: {
              gte: desde,
              lte: hasta,
            },
          },
          include: {
            insumo: true,
          },
        },
      },
    });

    if (!inventario) throw new Error("Inventario no encontrado");

    const resumen = new Map<number, { insumo: any; cantidad: number }>();

    for (const consumo of inventario.consumos) {
      const existente = resumen.get(consumo.insumo.id);
      if (existente) {
        existente.cantidad += consumo.cantidad;
      } else {
        resumen.set(consumo.insumo.id, {
          insumo: consumo.insumo,
          cantidad: consumo.cantidad,
        });
      }
    }

    return Array.from(resumen.values());
  }

  async tareasPorEstado(
    conjuntoId: number,
    estado: EstadoTarea,
    desde: Date,
    hasta: Date
  ) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado,
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      include: {
        ubicacion: true,
        elemento: true,
        operario: true,
      },
    });
  }

  async tareasConDetalle(
    conjuntoId: number,
    estado: EstadoTarea,
    desde: Date,
    hasta: Date
  ) {
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado,
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      include: {
        ubicacion: true,
        elemento: true,
        operario: {
          include: {
            usuario: true, // Aquí se incluye el nombre desde Usuario
          },
        },
      },
    });

    return tareas.map((t) => ({
      descripcion: t.descripcion,
      ubicacion: t.ubicacion?.nombre ?? "Sin ubicación",
      elemento: t.elemento?.nombre ?? "Sin elemento",
      responsable: t.operario?.usuario?.nombre ?? "Sin asignar",
      estado: t.estado,
    }));
  }

}
