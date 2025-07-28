import { PrismaClient } from '../generated/prisma';

export class CronogramaService {
  constructor(private prisma: PrismaClient, private conjuntoId: string) {}

  async tareasPorOperario(operarioId: number) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarioId: operarioId
      }
    });
  }

  async tareasPorFecha(fecha: Date) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha }
      }
    });
  }

  async tareasEnRango(fechaInicio: Date, fechaFin: Date) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaFin: { gte: fechaInicio },
        fechaInicio: { lte: fechaFin }
      }
    });
  }

  async tareasPorUbicacion(nombreUbicacion: string) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        ubicacion: {
          nombre: { equals: nombreUbicacion, mode: "insensitive" }
        }
      }
    });
  }

  async tareasPorFiltro(opciones: {
    operarioId?: number;
    fechaExacta?: Date;
    fechaInicio?: Date;
    fechaFin?: Date;
    ubicacion?: string;
  }) {
    return await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarioId: opciones.operarioId,
        fechaInicio: opciones.fechaExacta ? { lte: opciones.fechaExacta } : opciones.fechaInicio ? { lte: opciones.fechaFin } : undefined,
        fechaFin: opciones.fechaExacta ? { gte: opciones.fechaExacta } : opciones.fechaFin ? { gte: opciones.fechaInicio } : undefined,
        ubicacion: opciones.ubicacion
          ? { nombre: { equals: opciones.ubicacion, mode: "insensitive" } }
          : undefined
      }
    });
  }

  async exportarComoEventosCalendario() {
    const tareas = await this.prisma.tarea.findMany({
      where: { conjuntoId: this.conjuntoId },
      include: {
        ubicacion: true,
        elemento: true,
        operario: {
          include: {
            usuario: true
          }
        }
      }
    });

    return tareas.map(t => ({
      title: `${t.descripcion} - ${t.operario.usuario.nombre}`,
      start: t.fechaInicio.toISOString(),
      end: t.fechaFin.toISOString(),
      resource: {
        operario: t.operario.usuario.nombre,
        ubicacion: t.ubicacion.nombre,
        elemento: t.elemento.nombre
      }
    }));
  }
}
