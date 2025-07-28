import { PrismaClient } from '../generated/prisma';

export class MaquinariaService {
  constructor(private prisma: PrismaClient, private maquinariaId: number) {}

  async asignarAConjunto(conjuntoId: string, responsableId?: number, diasPrestamo: number = 7) {
    const fechaPrestamo = new Date();
    const fechaDevolucionEstimada = new Date(
      fechaPrestamo.getTime() + diasPrestamo * 24 * 60 * 60 * 1000
    );

    return await this.prisma.maquinaria.update({
      where: { id: this.maquinariaId },
      data: {
        asignadaA: { connect: { nit: conjuntoId } },
        responsable: responsableId ? { connect: { id: responsableId } } : undefined,
        fechaPrestamo,
        fechaDevolucionEstimada,
        disponible: false,
      }
    });
  }

  async devolver() {
    return await this.prisma.maquinaria.update({
      where: { id: this.maquinariaId },
      data: {
        asignadaA: { disconnect: true },
        responsable: { disconnect: true },
        fechaPrestamo: null,
        fechaDevolucionEstimada: null,
        disponible: true
      }
    });
  }

  async estaDisponible(): Promise<boolean> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: { disponible: true }
    });

    return maquinaria?.disponible ?? false;
  }

  async obtenerResponsable(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      include: {
        responsable: {
          include: {
            usuario: true
          }
        }
      }
    });

    return maquinaria?.responsable?.usuario?.nombre ?? "Sin asignar";
  }

  async resumenEstado(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: {
        nombre: true,
        marca: true,
        estado: true,
        disponible: true
      }
    });

    if (!maquinaria) throw new Error("🛠️ Maquinaria no encontrada");

    return `🛠️ ${maquinaria.nombre} (${maquinaria.marca}) - ${maquinaria.estado} - ${
      maquinaria.disponible ? "Disponible" : "Prestada"
    }`;
  }
}
