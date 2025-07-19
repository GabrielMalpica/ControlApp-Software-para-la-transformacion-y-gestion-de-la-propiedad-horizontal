import { PrismaClient } from '../generated/prisma';
import { TareaService } from "./TareaServices";
import { InventarioService } from "./InventarioServices";

export class OperarioService {
  constructor(
    private prisma: PrismaClient,
    private operarioId: number,
    private empresaId: number
  ) {}

  async asignarTarea(tareaId: number): Promise<void> {
    const tarea = await this.prisma.tarea.findUnique({ where: { id: tareaId } });
    if (!tarea) throw new Error("❌ Tarea no encontrada");

    const horasSemana = await this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionHoras > 46) {
      const operario = await this.prisma.operario.findUnique({
        where: { id: this.operarioId },
        include: { usuario: true }
      });
      throw new Error(`❌ Supera el límite de 46 horas semanales para ${operario?.usuario?.nombre ?? "Operario"}`);
    }

    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { operarioId: this.operarioId }
    });
  }

  async iniciarTarea(tareaId: number) {
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.iniciarTarea();
  }

  async marcarComoCompletada(
    tareaId: number,
    evidencias: string[],
    inventarioService: InventarioService,
    insumosUsados: { insumoId: number; cantidad: number }[] = []
  ) {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: {
        conjunto: true, // Para obtener el conjuntoId
      },
    });

    if (tarea!.conjuntoId === null) {
      throw new Error("❌ La tarea no tiene un conjunto asignado.");
    }

    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId: tarea!.conjuntoId },
    });

    if (!inventario) throw new Error("❌ No se encontró inventario para el conjunto asignado a la tarea");

    // Consumir insumos usando el servicio
    await new TareaService(this.prisma, tareaId).marcarComoCompletadaConInsumos(
      insumosUsados,
      inventarioService
    );

    // Registrar cada consumo en la base de datos
    for (const { insumoId, cantidad } of insumosUsados) {
      const insumo = await this.prisma.insumo.findUnique({ where: { id: insumoId } });
      if (!insumo) {
        throw new Error(`❌ El insumo con ID ${insumoId} no está registrado.`);
      }

      await this.prisma.consumoInsumo.create({
        data: {
          inventarioId: inventario.id,
          insumoId,
          cantidad,
          fecha: new Date(),
          tareaId: tareaId,
          // Puedes agregar operarioId u observación si lo deseas
        },
      });
    }

    // Actualizar la tarea con evidencias
    await this.prisma.tarea.update({
      where: { id: tareaId },
      data: { evidencias },
    });
  }


  async marcarComoNoCompletada(tareaId: number) {
    const tareaService = new TareaService(this.prisma, tareaId);
    await tareaService.marcarNoCompletada();
  }

  async tareasDelDia(fecha: Date) {
    return await this.prisma.tarea.findMany({
      where: {
        operarioId: this.operarioId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha }
      }
    });
  }

  async listarTareas() {
    return await this.prisma.tarea.findMany({
      where: { operarioId: this.operarioId }
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
        fechaFin: { gte: inicio }
      },
      select: { duracionHoras: true }
    });

    return tareas.reduce((sum, t) => sum + t.duracionHoras, 0);
  }

  async horasRestantesEnSemana(fecha: Date): Promise<number> {
    const horas = await this.horasAsignadasEnSemana(fecha);
    return Math.max(0, 46 - horas);
  }

  async resumenDeHoras(fecha: Date): Promise<string> {
    const horas = await this.horasAsignadasEnSemana(fecha);
    const operario = await this.prisma.operario.findUnique({
      where: { id: this.operarioId },
      include: { usuario: true }
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
