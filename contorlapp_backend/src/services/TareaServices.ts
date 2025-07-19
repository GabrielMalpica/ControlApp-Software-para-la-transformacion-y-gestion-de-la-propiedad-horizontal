import { PrismaClient, EstadoTarea } from "../generated/prisma";

export class TareaService {
  constructor(private prisma: PrismaClient, private tareaId: number) {}

  async agregarEvidencia(imagen: string): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({ where: { id: this.tareaId } });
    const nuevasEvidencias = [...(tarea?.evidencias ?? []), imagen];

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: { evidencias: nuevasEvidencias }
    });
  }

  async iniciarTarea(): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({ where: { id: this.tareaId } });

    if (!tarea) throw new Error("Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.ASIGNADA) {
      throw new Error("Solo se puede iniciar una tarea que esté asignada.");
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.EN_PROCESO,
        fechaIniciarTarea: new Date()
      }
    });
  }

  async marcarComoCompletadaConInsumos(
    insumosUsados: { insumoId: number; cantidad: number }[],
    inventarioService: { consumirInsumoPorId: (id: number, cantidad: number) => Promise<void> }
  ): Promise<void> {
    for (const { insumoId, cantidad } of insumosUsados) {
      await inventarioService.consumirInsumoPorId(insumoId, cantidad);
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        insumosUsados,
        estado: EstadoTarea.PENDIENTE_APROBACION,
        fechaFinalizarTarea: new Date()
      }
    });
  }

  async marcarNoCompletada(): Promise<void> {
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.NO_COMPLETADA
      }
    });
  }

  async aprobarTarea(supervisorId: number): Promise<void> {
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.APROBADA,
        fechaVerificacion: new Date(),
        supervisor: {
          connect: { id: supervisorId }
        }
      }
    });
  }


  async rechazarTarea(supervisorId: number, observacion: string): Promise<void> {
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.RECHAZADA,
        supervisorId: supervisorId,
        fechaVerificacion: new Date(),
        observacionesRechazo: observacion
      }
    });
  }

  async resumen(): Promise<string> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      include: {
        operario: { include: { usuario: true } },
        ubicacion: true,
        elemento: true
      }
    });

    if (!tarea) throw new Error("Tarea no encontrada");

    return `📝 Tarea: ${tarea.descripcion}
👷 Operario: ${tarea.operario?.usuario?.nombre ?? "No asignado"}
📍 Ubicación: ${tarea.ubicacion?.nombre ?? "Sin ubicación"}
🔧 Elemento: ${tarea.elemento?.nombre ?? "Sin elemento"}
🕒 Duración estimada: ${tarea.duracionHoras}h
📅 Del ${tarea.fechaInicio.toLocaleDateString()} al ${tarea.fechaFin.toLocaleDateString()}
📌 Estado actual: ${tarea.estado}`;
  }
}
