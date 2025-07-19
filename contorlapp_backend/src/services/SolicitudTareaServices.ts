import { PrismaClient, EstadoSolicitud } from '../generated/prisma';

export class SolicitudTareaService {
  constructor(private prisma: PrismaClient, private solicitudId: number) {}

  async aprobar(): Promise<void> {
    const solicitud = await this.prisma.solicitudTarea.findUnique({
      where: { id: this.solicitudId },
    });

    if (!solicitud) throw new Error("❌ Solicitud no encontrada.");
    if (solicitud.estado !== EstadoSolicitud.PENDIENTE) {
      throw new Error("❌ Solo se pueden aprobar solicitudes pendientes.");
    }

    await this.prisma.solicitudTarea.update({
      where: { id: this.solicitudId },
      data: { estado: EstadoSolicitud.APROBADA },
    });
  }

  async rechazar(observacion: string): Promise<void> {
    const solicitud = await this.prisma.solicitudTarea.findUnique({
      where: { id: this.solicitudId },
    });

    if (!solicitud) throw new Error("❌ Solicitud no encontrada.");
    if (solicitud.estado !== EstadoSolicitud.PENDIENTE) {
      throw new Error("❌ Solo se pueden rechazar solicitudes pendientes.");
    }

    await this.prisma.solicitudTarea.update({
      where: { id: this.solicitudId },
      data: {
        estado: EstadoSolicitud.RECHAZADA,
        observaciones: observacion,
      },
    });
  }

  async estadoActual(): Promise<string> {
    const solicitud = await this.prisma.solicitudTarea.findUnique({
      where: { id: this.solicitudId },
    });

    if (!solicitud) throw new Error("❌ Solicitud no encontrada.");

    return `📋 Estado de la solicitud: ${solicitud.estado}${
      solicitud.observaciones ? " - Obs: " + solicitud.observaciones : ""
    }`;
  }
}
