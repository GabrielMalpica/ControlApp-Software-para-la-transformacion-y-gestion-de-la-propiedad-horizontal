import { PrismaClient, EstadoTarea } from '../generated/prisma';

export class SupervisorService {
  constructor(
    private prisma: PrismaClient,
    private supervisorId: number
  ) {}

  async recibirTareaFinalizada(tareaId: number): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("Solo se pueden verificar tareas completadas por el operario.");
    }

    // Podrías registrar este evento si lo deseas
  }

  async aprobarTarea(tareaId: number): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("No se puede aprobar una tarea que no está pendiente de aprobación.");
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        estado: "APROBADA",
        supervisor: { connect: { id: this.supervisorId } },
        fechaVerificacion: new Date(),
      },
    });
  }

  async rechazarTarea(tareaId: number, observaciones: string): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: {
        ubicacion: {
          include: {
            conjunto: true,
          },
        },
        elemento: true,
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== "PENDIENTE_APROBACION") {
      throw new Error("No se puede rechazar una tarea que no está pendiente de aprobación.");
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        estado: "RECHAZADA",
        supervisor: { connect: { id: this.supervisorId } },
        fechaVerificacion: new Date(),
        observacionesRechazo: observaciones,
      },
    });

    await this.prisma.solicitudTarea.create({
      data: {
        descripcion: tarea.descripcion,
        conjuntoId: tarea.ubicacion.conjunto.nit,
        ubicacionId: tarea.ubicacionId!,
        elementoId: tarea.elementoId!,
        duracionHoras: tarea.duracionHoras,
        estado: "PENDIENTE",
        id: tarea.id,
      },
    });
  }


  async listarTareasPendientes(): Promise<any[]> {
    return this.prisma.tarea.findMany({
      where: {
        estado: "PENDIENTE_APROBACION",
        supervisorId: this.supervisorId,
      },
    });
  }
}
