import { PrismaClient } from '../generated/prisma';

export class AdministradorService {
  constructor(private prisma: PrismaClient, private administradorId: number) {}

  async verConjuntos() {
    try {
      const conjuntos = await this.prisma.conjunto.findMany({
        where: { administradorId: this.administradorId }
      });
      return conjuntos.map(c => `${c.nombre} ${c.nit}`);
    } catch (error) {
      console.error("Error al obtener conjuntos:", error);
      throw new Error("No se pudieron obtener los conjuntos.");
    }
  }

  async solicitarTarea(
    descripcion: string,
    conjuntoId: number,
    ubicacionId: number,
    elementoId: number,
    duracionHoras: number
  ) {
    try {
      return await this.prisma.solicitudTarea.create({
        data: {
          descripcion,
          conjunto: { connect: { nit: conjuntoId } },
          ubicacion: { connect: { id: ubicacionId } },
          elemento: { connect: { id: elementoId } },
          duracionHoras,
          estado: "PENDIENTE"
        }
      });
    } catch (error) {
      console.error("Error al crear solicitud de tarea:", error);
      throw new Error("No se pudo registrar la solicitud de tarea.");
    }
  }

  async solicitarInsumos(
    conjuntoId: number,
    insumos: { insumoId: number; cantidad: number }[]
  ) {
    try {
      return await this.prisma.solicitudInsumo.create({
        data: {
          conjunto: { connect: { nit: conjuntoId } },
          insumosSolicitados: {
            create: insumos.map(({ insumoId, cantidad }) => ({
              insumo: { connect: { id: insumoId } },
              cantidad
            }))
          },
          fechaSolicitud: new Date(),
          aprobado: false
        }
      });
    } catch (error) {
      console.error("Error al crear solicitud de insumos:", error);
      throw new Error("No se pudo registrar la solicitud de insumos.");
    }
  }

  async solicitarMaquinaria(
    conjuntoId: number,
    maquinariaId: number,
    responsableId: number,
    fechaUso: Date,
    fechaDevolucion: Date
  ) {
    try {
      return await this.prisma.solicitudMaquinaria.create({
        data: {
          conjunto: { connect: { nit: conjuntoId } },
          maquinaria: { connect: { id: maquinariaId } },
          responsable: { connect: { id: responsableId } },
          fechaUso,
          fechaDevolucionEstimada: fechaDevolucion,
          fechaSolicitud: new Date(),
          aprobado: false
        }
      });
    } catch (error) {
      console.error("Error al crear solicitud de maquinaria:", error);
      throw new Error("No se pudo registrar la solicitud de maquinaria.");
    }
  }
}
