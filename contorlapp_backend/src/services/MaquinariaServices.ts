import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

const AsignarAConjuntoDTO = z.object({
  conjuntoId: z.string().min(3),
  responsableId: z.string().optional(), // ✅ Operario.id es String en tu schema
  diasPrestamo: z.number().int().positive().default(7),
});

export class MaquinariaService {
  constructor(private prisma: PrismaClient, private maquinariaId: number) {}

  async asignarAConjunto(payload: unknown) {
    const { conjuntoId, responsableId, diasPrestamo } =
      AsignarAConjuntoDTO.parse(payload);

    const fechaInicio = new Date();
    const fechaDevolucionEstimada = new Date(
      fechaInicio.getTime() + diasPrestamo * 24 * 60 * 60 * 1000
    );

    // 1) Validar existencia maquinaria y conjunto
    const [maq, conj] = await Promise.all([
      this.prisma.maquinaria.findUnique({
        where: { id: this.maquinariaId },
        select: { id: true },
      }),
      this.prisma.conjunto.findUnique({
        where: { nit: conjuntoId },
        select: { nit: true },
      }),
    ]);
    if (!maq) throw new Error("Maquinaria no encontrada");
    if (!conj) throw new Error("Conjunto no encontrado");

    // 2) Validar que NO esté ACTIVA en otro conjunto
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      select: { id: true, conjuntoId: true },
    });
    if (activa) {
      throw new Error(
        `La maquinaria ya está asignada (ACTIVA) al conjunto ${activa.conjuntoId}.`
      );
    }

    // 3) Crear asignación (inventario del conjunto)
    return this.prisma.maquinariaConjunto.create({
      data: {
        conjunto: { connect: { nit: conjuntoId } },
        maquinaria: { connect: { id: this.maquinariaId } },
        tipoTenencia: "PRESTADA",
        estado: "ACTIVA",
        fechaInicio,
        fechaDevolucionEstimada,
        ...(responsableId
          ? { responsable: { connect: { id: responsableId } } }
          : {}),
      },
      include: {
        conjunto: { select: { nit: true, nombre: true } },
        maquinaria: {
          select: { id: true, nombre: true, marca: true, estado: true },
        },
        responsable: { include: { usuario: { select: { nombre: true } } } },
      },
    });
  }

  async devolver(conjuntoId: string) {
    // 1) Buscar asignación ACTIVA en ese conjunto
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: {
        maquinariaId: this.maquinariaId,
        conjuntoId,
        estado: "ACTIVA",
      },
      select: { id: true },
    });

    if (!activa) {
      throw new Error(
        "No existe una asignación ACTIVA de esta maquinaria en ese conjunto."
      );
    }

    // 2) Cerrar asignación
    return this.prisma.maquinariaConjunto.update({
      where: { id: activa.id },
      data: {
        estado: "DEVUELTA",
        fechaFin: new Date(),
      },
    });
  }

  async estaDisponible(): Promise<boolean> {
    // Disponible si NO tiene asignación ACTIVA
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      select: { id: true },
    });
    return !activa;
  }

  async obtenerResponsableEnConjunto(conjuntoId: string): Promise<string> {
    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: {
        maquinariaId: this.maquinariaId,
        conjuntoId,
        estado: "ACTIVA",
      },
      include: { responsable: { include: { usuario: true } } },
    });

    return activa?.responsable?.usuario?.nombre ?? "Sin asignar";
  }

  async resumenEstado(): Promise<string> {
    const maquinaria = await this.prisma.maquinaria.findUnique({
      where: { id: this.maquinariaId },
      select: { nombre: true, marca: true, estado: true },
    });
    if (!maquinaria) throw new Error("🛠️ Maquinaria no encontrada");

    const activa = await this.prisma.maquinariaConjunto.findFirst({
      where: { maquinariaId: this.maquinariaId, estado: "ACTIVA" },
      include: { conjunto: { select: { nombre: true } } },
    });

    const estadoAsignacion = activa
      ? `Prestada a ${activa.conjunto?.nombre ?? activa.conjuntoId}`
      : "Disponible";

    return `🛠️ ${maquinaria.nombre} (${maquinaria.marca}) - ${maquinaria.estado} - ${estadoAsignacion}`;
  }
}
