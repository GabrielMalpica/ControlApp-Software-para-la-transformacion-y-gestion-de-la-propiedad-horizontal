import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

const AsignarAConjuntoDTO = z.object({
  conjuntoId: z.string().min(3),
  responsableId: z.number().int().positive().optional(),
  diasPrestamo: z.number().int().positive().default(7),
});

export class MaquinariaService {
  constructor(private prisma: PrismaClient, private maquinariaId: number) {}

  async asignarAConjunto(payload: unknown) {
    const { conjuntoId, responsableId, diasPrestamo } = AsignarAConjuntoDTO.parse(payload);

    const fechaPrestamo = new Date();
    const fechaDevolucionEstimada = new Date(
      fechaPrestamo.getTime() + diasPrestamo * 24 * 60 * 60 * 1000
    );

    // Validaciones mínimas
    const [maq, conj] = await Promise.all([
      this.prisma.maquinaria.findUnique({ where: { id: this.maquinariaId }, select: { id: true, disponible: true } }),
      this.prisma.conjunto.findUnique({ where: { nit: conjuntoId }, select: { nit: true } }),
    ]);
    if (!maq) throw new Error("Maquinaria no encontrada");
    if (!maq.disponible) throw new Error("La maquinaria no está disponible.");
    if (!conj) throw new Error("Conjunto no encontrado");

    return this.prisma.maquinaria.update({
      where: { id: this.maquinariaId },
      data: {
        asignadaA: { connect: { nit: conjuntoId } },
        responsable: responsableId ? { connect: { id: responsableId } } : undefined,
        fechaPrestamo,
        fechaDevolucionEstimada,
        disponible: false,
      },
    });
  }

  async devolver() {
    // Opcional: validar que esté asignada
    return this.prisma.maquinaria.update({
      where: { id: this.maquinariaId },
      data: {
        asignadaA: { disconnect: true },
        responsable: { disconnect: true },
        fechaPrestamo: null,
        fechaDevolucionEstimada: null,
        disponible: true,
      },
    });
  }

  async estaDisponible(): Promise<boolean> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: { disponible: true },
    });
    return maquinaria?.disponible ?? false;
  }

  async obtenerResponsable(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      include: { responsable: { include: { usuario: true } } },
    });
    return maquinaria?.responsable?.usuario?.nombre ?? "Sin asignar";
  }

  async resumenEstado(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: { nombre: true, marca: true, estado: true, disponible: true },
    });
    if (!maquinaria) throw new Error("🛠️ Maquinaria no encontrada");

    return `🛠️ ${maquinaria.nombre} (${maquinaria.marca}) - ${maquinaria.estado} - ${
      maquinaria.disponible ? "Disponible" : "Prestada"
    }`;
    }
}
