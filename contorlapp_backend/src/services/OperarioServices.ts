import { Operario } from "../model/Operario";
import { Tarea } from "../model/Tarea";
import { TareaService } from "./TareaServices";
import { InventarioService } from "./InventarioServices";
import { Empresa } from "../model/Empresa";
import { Insumo } from "../model/Insumo";

export class OperarioService {
  constructor(private operario: Operario, private empresa: Empresa) {}

  asignarTarea(tarea: Tarea): void {
    const horasSemana = this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionHoras > Operario.LIMITE_SEMANAL_HORAS) {
      throw new Error(`❌ Supera el límite de 46 horas semanales para ${this.operario.nombre}`);
    }
    this.operario.tareas.push(tarea);
  }

    iniciarTarea(tareaId: number): void {
    const tarea = this.buscarTarea(tareaId);

    const tareaService = new TareaService(tarea);
    tareaService.iniciarTarea();
  }



  marcarComoCompletada(
    tareaId: number,
    evidencias: string[],
    inventarioService: InventarioService,
    insumosUsados: { insumoId: number; cantidad: number }[] = []
  ): void {
    const tarea = this.buscarTarea(tareaId);
    tarea.evidencias = evidencias;

    const tareaService = new TareaService(tarea);
    tareaService.marcarComoCompletadaConInsumos(insumosUsados, inventarioService);

    insumosUsados.forEach(({ insumoId, cantidad }) => {
      const insumo = this.empresa.catalogoInsumos.find(i => i.id === insumoId);
      if (!insumo) {
        throw new Error(`❌ El insumo con ID ${insumoId} no está registrado en el catálogo de la empresa.`);
      }
      this.registrarConsumo(insumo, cantidad);
    });
  }


  marcarComoNoCompletada(tareaId: number): void {
    const tarea = this.buscarTarea(tareaId);
    const tareaService = new TareaService(tarea);
    tareaService.marcarNoCompletada();
  }

  tareasDelDia(fecha: Date): Tarea[] {
    return this.operario.tareas.filter(t => fecha >= t.fechaInicio && fecha <= t.fechaFin);
  }

  listarTareas(): Tarea[] {
    return this.operario.tareas;
  }

  horasAsignadasEnSemana(fecha: Date): number {
    const start = this.inicioSemana(fecha);
    const end = new Date(start);
    end.setDate(start.getDate() + 6);

    return this.operario.tareas
      .filter(t => t.fechaInicio <= end && t.fechaFin >= start)
      .reduce((sum, t) => sum + t.duracionHoras, 0);
  }

  horasRestantesEnSemana(fecha: Date): number {
    return Math.max(0, Operario.LIMITE_SEMANAL_HORAS - this.horasAsignadasEnSemana(fecha));
  }

  resumenDeHoras(fecha: Date): string {
    const horas = this.horasAsignadasEnSemana(fecha);
    return `🔔 A ${this.operario.nombre} le quedan ${Operario.LIMITE_SEMANAL_HORAS - horas}h disponibles esta semana.`;
  }

  // ─── Helpers ───────────────────────────────────────────────
  private buscarTarea(tareaId: number): Tarea {
    const tarea = this.operario.tareas.find(t => t.id === tareaId);
    if (!tarea) throw new Error("❌ Tarea no encontrada");
    return tarea;
  }

  private inicioSemana(fecha: Date): Date {
    const day = fecha.getDay();
    const diff = fecha.getDate() - day + (day === 0 ? -6 : 1); // Lunes como día 1
    return new Date(fecha.getFullYear(), fecha.getMonth(), diff);
  }

  registrarConsumo(insumo: Insumo, cantidad: number): void {
    this.empresa.insumosConsumidos.push({ insumo, cantidad, fecha: new Date() });
  }
}
