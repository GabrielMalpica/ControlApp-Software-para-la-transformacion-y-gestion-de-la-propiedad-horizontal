import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";

const EvidenciaDTO = z.object({ imagen: z.string().min(1) });
const ConsumoItemDTO = z.object({
  insumoId: z.number().int().positive(),
  cantidad: z.number().int().positive(),
});
const CompletarConInsumosDTO = z.object({
  insumosUsados: z.array(ConsumoItemDTO).default([]),
});
const SupervisorIdDTO = z.object({ supervisorId: z.number().int().positive() });
const RechazarDTO = z.object({
  supervisorId: z.number().int().positive(),
  observacion: z.string().min(3).max(500),
});

export class TareaService {
  constructor(private prisma: PrismaClient, private tareaId: number) {}

  async agregarEvidencia(payload: unknown): Promise<void> {
    const { imagen } = EvidenciaDTO.parse(payload);
    const tarea = await this.prisma.tarea.findUnique({ where: { id: this.tareaId } });
    if (!tarea) throw new Error("Tarea no encontrada.");

    const nuevasEvidencias = [...(tarea.evidencias ?? []), imagen];
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: { evidencias: nuevasEvidencias },
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
        fechaIniciarTarea: new Date(),
      },
    });
  }

  async marcarComoCompletadaConInsumos(
    payload: unknown,
    inventarioService: { consumirInsumoPorId: (payload: unknown) => Promise<void> }
  ): Promise<void> {
    const { insumosUsados } = CompletarConInsumosDTO.parse(payload);

    for (const { insumoId, cantidad } of insumosUsados) {
      await inventarioService.consumirInsumoPorId({ insumoId, cantidad }); // ✅ objeto
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        insumosUsados,
        estado: "PENDIENTE_APROBACION",
        fechaFinalizarTarea: new Date(),
      },
    });
  }

  async marcarNoCompletada(): Promise<void> {
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: { estado: EstadoTarea.NO_COMPLETADA },
    });
  }

  async aprobarTarea(payload: unknown): Promise<void> {
    const { supervisorId } = SupervisorIdDTO.parse(payload);
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.APROBADA,
        fechaVerificacion: new Date(),
        supervisor: { connect: { id: supervisorId } },
      },
    });
  }

  async rechazarTarea(payload: unknown): Promise<void> {
    const { supervisorId, observacion } = RechazarDTO.parse(payload);
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.RECHAZADA,
        supervisorId,
        fechaVerificacion: new Date(),
        observacionesRechazo: observacion,
      },
    });
  }

  async resumen(): Promise<string> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      include: {
        operario: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
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
