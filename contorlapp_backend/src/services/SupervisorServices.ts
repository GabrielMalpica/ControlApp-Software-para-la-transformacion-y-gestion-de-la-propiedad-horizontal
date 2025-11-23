import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";

const TareaIdDTO = z.object({ tareaId: z.number().int().positive() });
const RechazarDTO = z.object({
  tareaId: z.number().int().positive(),
  observaciones: z.string().min(3).max(500),
});

export class SupervisorService {
  constructor(
    private prisma: PrismaClient,
    private supervisorId: number
  ) {}

  async recibirTareaFinalizada(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("Solo se pueden verificar tareas completadas por el operario.");
    }
    // aquí podrías loguear el evento si quieres
  }

  async aprobarTarea(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("No se puede aprobar una tarea que no está pendiente de aprobación.");
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        estado: EstadoTarea.APROBADA,
        supervisor: { connect: { id: this.supervisorId.toString() } },
        fechaVerificacion: new Date(),
      },
    });
  }

  async rechazarTarea(payload: unknown): Promise<void> {
    const { tareaId, observaciones } = RechazarDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: {
        ubicacion: { include: { conjunto: true } },
        elemento: true,
      },
    });

    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("No se puede rechazar una tarea que no está pendiente de aprobación.");
    }

    // 1) Marcar rechazada
    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        estado: EstadoTarea.RECHAZADA,
        supervisor: { connect: { id: this.supervisorId.toString() } },
        fechaVerificacion: new Date(),
        observacionesRechazo: observaciones,
      },
    });

    // 2) Re-abrir como solicitud (NO reusar id, dejar autoincrement!)
    await this.prisma.solicitudTarea.create({
      data: {
        descripcion: tarea.descripcion,
        conjunto: { connect: { nit: tarea.ubicacion!.conjunto.nit } },
        ubicacion: { connect: { id: tarea.ubicacionId! } },
        elemento: { connect: { id: tarea.elementoId! } },
        duracionHoras: tarea.duracionHoras,
        estado: "PENDIENTE",
      },
    });
  }

  async listarTareasPendientes(): Promise<any[]> {
    return this.prisma.tarea.findMany({
      where: {
        estado: EstadoTarea.PENDIENTE_APROBACION,
        supervisorId: this.supervisorId.toString(), // si quieres ver “propias”
      },
    });
  }
}
