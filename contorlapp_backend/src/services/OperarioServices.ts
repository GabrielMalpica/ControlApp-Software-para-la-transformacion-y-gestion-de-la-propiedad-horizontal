// src/services/OperarioService.ts
import { PrismaClient } from "../generated/prisma";
import { z } from "zod";
import { TareaService } from "./TareaServices";
import { InventarioService } from "./InventarioServices";

const TareaIdDTO = z.object({ tareaId: z.number().int().positive() });

const MarcarCompletadaDTO = z.object({
  tareaId: z.number().int().positive(),
  evidencias: z.array(z.string()).default([]),
  insumosUsados: z
    .array(
      z.object({
        insumoId: z.number().int().positive(),
        cantidad: z.number().int().positive(),
      })
    )
    .default([]),
});

const FechaDTO = z.object({ fecha: z.coerce.date() });

export class OperarioService {
  constructor(private prisma: PrismaClient, private operarioId: number) {}

  /** Obtiene el límite semanal (horas) desde la Empresa del operario */
  private async getLimiteHorasSemana(): Promise<number> {
    const op = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return op?.empresa?.limiteHorasSemana ?? 46;
  }

  /** Asigna una tarea al operario respetando el límite semanal empresarial */
  async asignarTarea(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { fechaInicio: true, duracionMinutos: true, id: true },
    });
    if (!tarea) throw new Error("❌ Tarea no encontrada");

    const limite = await this.getLimiteHorasSemana();
    const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionMinutos > limite) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: this.operarioId.toString() },
        include: { usuario: true },
      });
      const nombre = operario?.usuario?.nombre ?? "Operario";
      throw new Error(
        `❌ Supera el límite de ${limite} horas semanales para ${nombre}`
      );
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { operarios: { connect: { id: this.operarioId.toString() } } },
    });
  }

  /** Inicia una tarea (cambia estado a EN_PROCESO) */
  async iniciarTarea(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.iniciarTarea();
  }

  /**
   * Marca tarea como completada y consume insumos.
   * - Usa InventarioService para registrar el consumo (con operarioId/tareaId si tu versión lo soporta).
   * - Cambia estado a PENDIENTE_APROBACION (lo hace TareaService).
   * - Actualiza evidencias.
   */
  async marcarComoCompletada(
    payload: unknown,
    inventarioService: InventarioService
  ) {
    const { tareaId, evidencias, insumosUsados } =
      MarcarCompletadaDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { conjunto: true },
    });
    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.conjuntoId === null) {
      throw new Error("❌ La tarea no tiene un conjunto asignado.");
    }

    // Si tu InventarioService.consumirInsumoPorId acepta metadata (operarioId/tareaId),
    // puedes pasarla así para evitar duplicados y tener mejor trazabilidad.
    // Ej: await inventarioService.consumirInsumoPorId({ insumoId, cantidad, operarioId: this.operarioId, tareaId })
    await new TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos(
      { insumosUsados },
      {
        // Adapter que cumple con (payload: unknown) => Promise<void>
        consumirInsumoPorId: async (payload: unknown) => {
          // valida/extrae campos con Zod (opcional pero recomendado)
          const p = z
            .object({
              insumoId: z.number().int().positive(),
              cantidad: z.number().int().positive(),
            })
            .parse(payload);

          // llama a tu InventarioService con el shape que ya acepta
          // si en tu InventarioService agregaste metadata (operarioId/tareaId),
          // complétala aquí.
          await (inventarioService as any).consumirInsumoPorId({
            insumoId: p.insumoId,
            cantidad: p.cantidad,
            // operarioId: this.operarioId,
            // tareaId,
          });
        },
      }
    );

    // Guardar/mergear evidencias (no lo hace TareaService)
    const actuales =
      (
        await this.prisma.tarea.findUnique({
          where: { id: tareaId },
          select: { evidencias: true },
        })
      )?.evidencias ?? [];

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { evidencias: [...actuales, ...evidencias] },
    });
  }

  /** Marca una tarea como NO_COMPLETADA */
  async marcarComoNoCompletada(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.marcarNoCompletada();
  }

  /** Tareas del día para este operario */
  async tareasDelDia(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async listarTareas() {
    return this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
      },
      orderBy: { fechaInicio: "asc" },
      include: {
        ubicacion: true,
        elemento: true,
        conjunto: true,
      },
    });
  }

  /** Suma de horas en la semana (lunes a domingo) de la fecha dada */
  async horasAsignadasEnSemana(fecha: Date): Promise<number> {
    const inicio = this.inicioSemana(fecha);
    const fin = new Date(inicio);
    fin.setDate(inicio.getDate() + 6);
    fin.setHours(23, 59, 59, 999);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        operarios: { some: { id: this.operarioId.toString() } },
        fechaFin: { gte: inicio },
        fechaInicio: { lte: fin },
      },
      select: { duracionMinutos: true },
    });

    return tareas.reduce((sum, t) => sum + t.duracionMinutos, 0);
  }

  async horasRestantesEnSemana(payload: unknown): Promise<number> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    return Math.max(0, limite - horas);
  }

  async resumenDeHoras(payload: unknown): Promise<string> {
    const { fecha } = FechaDTO.parse(payload);
    const limite = await this.getLimiteHorasSemana();
    const horas = await this.horasAsignadasEnSemana(fecha);
    const operario = await this.prisma.operario.findUnique({
      where: { id: this.operarioId.toString() },
      include: { usuario: true },
    });
    const nombre = operario?.usuario?.nombre ?? "Operario";
    return `🔔 A ${nombre} le quedan ${Math.max(
      0,
      limite - horas
    )}h disponibles esta semana (límite ${limite}h).`;
    // si quieres, puedes retornar también { horasAsignadas: horas, limite, restantes: limite - horas }
  }

  /** Lunes de la semana ISO de la fecha dada */
  private inicioSemana(fecha: Date): Date {
    const d = new Date(fecha);
    const day = d.getDay(); // 0=Dom ... 6=Sab
    const diff = d.getDate() - day + (day === 0 ? -6 : 1); // Lunes
    return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
  }
}
