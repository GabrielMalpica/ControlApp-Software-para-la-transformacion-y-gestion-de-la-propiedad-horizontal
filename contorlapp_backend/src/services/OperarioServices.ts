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
  constructor(
    private prisma: PrismaClient,
    private operarioId: number,
  ) {}

  // Antes: asignarTarea(tareaId: number)
  async asignarTarea(payload: unknown): Promise<void> {
    const { tareaId } = TareaIdDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });
    if (!tarea) throw new Error("❌ Tarea no encontrada");

    const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionHoras > 46) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: this.operarioId },
        include: { usuario: true },
      });
      throw new Error(
        `❌ Supera el límite de 46 horas semanales para ${operario?.usuario?.nombre ?? "Operario"}`
      );
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { operarioId: this.operarioId },
    });
  }

  // Antes: iniciarTarea(tareaId: number)
  async iniciarTarea(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.iniciarTarea();
  }

  /**
   * Antes:
   * marcarComoCompletada(tareaId, evidencias, inventarioService, insumosUsados)
   * Ahora: pasas { tareaId, evidencias, insumosUsados } y el inventarioService lo recibes como arg
   */
  async marcarComoCompletada(
    payload: unknown,
    inventarioService: InventarioService
  ) {
    const { tareaId, evidencias, insumosUsados } = MarcarCompletadaDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { conjunto: true },
    });
    if (!tarea) throw new Error("❌ Tarea no encontrada.");
    if (tarea.conjuntoId === null) throw new Error("❌ La tarea no tiene un conjunto asignado.");

    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId: tarea.conjuntoId },
    });
    if (!inventario)
      throw new Error("❌ No se encontró inventario para el conjunto asignado a la tarea");

    // Consumir insumos con servicio de Tarea (tu lógica existente)
    await new TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos(
      { insumosUsados },
      inventarioService
    );


    // Registrar consumos
    for (const { insumoId, cantidad } of insumosUsados) {
      const insumo = await this.prisma.insumo.findUnique({ where: { id: insumoId } });
      if (!insumo) throw new Error(`❌ El insumo con ID ${insumoId} no está registrado.`);

      await this.prisma.consumoInsumo.create({
        data: {
          inventarioId: inventario.id,
          insumoId,
          cantidad,
          fecha: new Date(),
          tareaId,
        },
      });
    }

    // Guardar evidencias
    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { evidencias },
    });
  }

  // Antes: marcarComoNoCompletada(tareaId)
  async marcarComoNoCompletada(payload: unknown) {
    const { tareaId } = TareaIdDTO.parse(payload);
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.marcarNoCompletada();
  }

  // Antes: tareasDelDia(fecha: Date)
  async tareasDelDia(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        operarioId: this.operarioId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async listarTareas() {
    return this.prisma.tarea.findMany({
      where: { operarioId: this.operarioId },
    });
  }

  async horasAsignadasEnSemana(fecha: Date): Promise<number> {
    const inicio = this.inicioSemana(fecha);
    const fin = new Date(inicio);
    fin.setDate(inicio.getDate() + 6);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        operarioId: this.operarioId,
        fechaInicio: { lte: fin },
        fechaFin: { gte: inicio },
      },
      select: { duracionHoras: true },
    });

    return tareas.reduce((sum, t) => sum + t.duracionHoras, 0);
  }

  async horasRestantesEnSemana(payload: unknown): Promise<number> {
    const { fecha } = FechaDTO.parse(payload);
    const horas = await this.horasAsignadasEnSemana(fecha);
    return Math.max(0, 46 - horas);
  }

  async resumenDeHoras(payload: unknown): Promise<string> {
    const { fecha } = FechaDTO.parse(payload);
    const horas = await this.horasAsignadasEnSemana(fecha);
    const operario = await this.prisma.operario.findUnique({
      where: { id: this.operarioId },
      include: { usuario: true },
    });
    const nombre = operario?.usuario?.nombre ?? "Operario";
    return `🔔 A ${nombre} le quedan ${46 - horas}h disponibles esta semana.`;
  }

  private inicioSemana(fecha: Date): Date {
    const day = fecha.getDay();
    const diff = fecha.getDate() - day + (day === 0 ? -6 : 1);
    return new Date(fecha.getFullYear(), fecha.getMonth(), diff);
  }
}
