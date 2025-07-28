import { PrismaClient } from '../generated/prisma';

export class ConjuntoService {
  constructor(
    private prisma: PrismaClient,
    private conjuntoId: string // corresponde al `nit`
  ) {}

  async asignarOperario(operarioId: number) {
    try {
      // Relación N:N en tabla intermedia
      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          operarios: {
            connect: { id: operarioId }
          }
        }
      });
    } catch (error) {
      console.error("Error al asignar operario:", error);
      throw new Error("No se pudo asignar el operario.");
    }
  }

  async asignarAdministrador(administradorId: number) {
    try {
      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          administrador: {
            connect: { id: administradorId }
          }
        }
      });
    } catch (error) {
      console.error("Error al asignar administrador:", error);
      throw new Error("No se pudo asignar el administrador.");
    }
  }

  async eliminarAdministrador() {
    try {
      await this.prisma.conjunto.update({
        where: { nit: this.conjuntoId },
        data: {
          administradorId: null
        }
      });
    } catch (error) {
      console.error("Error al eliminar administrador:", error);
      throw new Error("No se pudo eliminar el administrador.");
    }
  }

  async agregarMaquinaria(maquinariaId: number) {
    try {
      await this.prisma.maquinaria.update({
        where: { id: maquinariaId },
        data: {
          conjuntoId: this.conjuntoId
        }
      });
    } catch (error) {
      console.error("Error al agregar maquinaria al conjunto:", error);
      throw new Error("No se pudo asignar la maquinaria al conjunto.");
    }
  }

  async entregarMaquinaria(maquinariaId: number) {
    try {
      await this.prisma.maquinaria.update({
        where: { id: maquinariaId },
        data: {
          conjuntoId: null
        }
      });
    } catch (error) {
      console.error("Error al devolver maquinaria:", error);
      throw new Error("No se pudo devolver la maquinaria.");
    }
  }

  async agregarUbicacion(nombre: string) {
    try {
      const yaExiste = await this.prisma.ubicacion.findFirst({
        where: {
          nombre,
          conjuntoId: this.conjuntoId
        }
      });

      if (!yaExiste) {
        await this.prisma.ubicacion.create({
          data: {
            nombre,
            conjunto: {
              connect: { nit: this.conjuntoId }
            }
          }
        });
      }
    } catch (error) {
      console.error("Error al agregar ubicación:", error);
      throw new Error("No se pudo agregar la ubicación.");
    }
  }

  async buscarUbicacion(nombre: string) {
    return this.prisma.ubicacion.findFirst({
      where: {
        nombre,
        conjuntoId: this.conjuntoId
      }
    });
  }

  async agregarTareaACronograma(tareaId: number) {
    try {
      await this.prisma.tarea.update({
        where: { id: tareaId },
        data: {
          conjunto: {
            connect: { nit: this.conjuntoId }
          }
        }
      });
    } catch (error) {
      console.error("Error al agregar tarea al cronograma:", error);
      throw new Error("No se pudo agregar la tarea al cronograma.");
    }
  }

  async tareasPorFecha(fecha: Date) {
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha }
      }
    });
  }

  async tareasPorOperario(operarioId: number) {
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarioId
      }
    });
  }

  async tareasPorUbicacion(nombreUbicacion: string) {
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        ubicacion: {
          nombre: nombreUbicacion
        }
      }
    });
  }
}
