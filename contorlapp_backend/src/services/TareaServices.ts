// src/services/TareaService.ts
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

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      select: { evidencias: true },
    });
    if (!tarea) throw new Error("Tarea no encontrada.");

    const evidencias = Array.isArray(tarea.evidencias) ? tarea.evidencias : [];
    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: { evidencias: [...evidencias, imagen] },
    });
  }

  async iniciarTarea(): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      select: { estado: true },
    });

    if (!tarea) throw new Error("Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.ASIGNADA) {
      throw new Error("Solo se puede iniciar una tarea que esté ASIGNADA.");
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.EN_PROCESO,
        fechaIniciarTarea: new Date(),
      },
    });
  }

  /**
   * Marca tarea como completada y registra consumos de insumos en una transacción.
   * Si algún consumo falla (stock insuficiente, etc.), NO se cambia el estado de la tarea.
   */
  async marcarComoCompletadaConInsumos(
    payload: unknown,
    inventarioService: {
      consumirInsumoPorId: (payload: unknown) => Promise<void>;
    }
  ): Promise<void> {
    const { insumosUsados } = CompletarConInsumosDTO.parse(payload);

    await this.prisma.$transaction(async () => {
      // 1) Consumir insumos (si falla, aborta la transacción)
      for (const { insumoId, cantidad } of insumosUsados) {
        await inventarioService.consumirInsumoPorId({ insumoId, cantidad });
      }

      // 2) Cambiar estado -> PENDIENTE_APROBACION y guardar snapshot de insumosUsados
      await this.prisma.tarea.update({
        where: { id: this.tareaId },
        data: {
          insumosUsados, // Json
          estado: EstadoTarea.PENDIENTE_APROBACION,
          fechaFinalizarTarea: new Date(),
        },
      });
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

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      select: { estado: true },
    });
    if (!tarea) throw new Error("Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("Solo se puede aprobar una tarea PENDIENTE_APROBACION.");
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.APROBADA,
        fechaVerificacion: new Date(),
        supervisor: { connect: { id: supervisorId.toString() } },
      },
    });
  }

  async rechazarTarea(payload: unknown): Promise<void> {
    const { supervisorId, observacion } = RechazarDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      select: { estado: true },
    });
    if (!tarea) throw new Error("Tarea no encontrada.");
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("Solo se puede rechazar una tarea PENDIENTE_APROBACION.");
    }

    await this.prisma.tarea.update({
      where: { id: this.tareaId },
      data: {
        estado: EstadoTarea.RECHAZADA,
        supervisorId: supervisorId == null ? null : supervisorId.toString(),
        fechaVerificacion: new Date(),
        observacionesRechazo: observacion,
      },
    });
  }

  async resumen(): Promise<string> {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: this.tareaId },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
    });

    const operarios =
      tarea!.operarios?.map((o) => o.usuario?.nombre).filter(Boolean) ?? [];
    const operariosTxt = operarios.length
      ? operarios.join(", ")
      : "No asignados";

    return `📝 Tarea: ${tarea!.descripcion}
👷 Operarios: ${operariosTxt}
📍 Ubicación: ${tarea!.ubicacion?.nombre ?? "Sin ubicación"}
🔧 Elemento: ${tarea!.elemento?.nombre ?? "Sin elemento"}
🕒 Duración estimada: ${tarea!.duracionHoras}h
📅 Del ${tarea!.fechaInicio.toLocaleDateString()} al ${tarea!.fechaFin.toLocaleDateString()}
📌 Estado actual: ${tarea!.estado}`;
  }
}
