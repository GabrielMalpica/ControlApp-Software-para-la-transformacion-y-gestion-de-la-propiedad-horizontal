import { Usuario } from "./usuario";
import { TipoFuncion } from "./enum/tipoFuncion";
import { Tarea } from "./tarea";

export class Operario extends Usuario {
  funciones: TipoFuncion[];
  tareas: Tarea[] = [];
  static LIMITE_SEMANAL_HORAS = 46;

  constructor(id: number, nombre: string, correo: string, funciones: TipoFuncion[]) {
    super(id, nombre, correo, 'operario');
    this.funciones = funciones;
  }

  asignarTarea(tarea: Tarea): void {
    const horasSemana = this.horasAsignadasEnSemana(tarea.fechaInicio);
    if (horasSemana + tarea.duracionHoras > Operario.LIMITE_SEMANAL_HORAS) {
      throw new Error(`❌ Supera el límite de 46 horas semanales para ${this.nombre}`);
    }
    this.tareas.push(tarea);
  }

  marcarComoCompletada(tareaId: number, evidencias: string[]): void {
    const tarea = this.tareas.find(t => t.id === tareaId);
    if (!tarea) throw new Error("❌ Tarea no encontrada");

    tarea.evidencias = evidencias;
    tarea.marcarComoCompletada(); // método de clase Tarea
  }

  marcarComoNoCompletada(tareaId: number): void {
    const tarea = this.tareas.find(t => t.id === tareaId);
    if (!tarea) throw new Error("❌ Tarea no encontrada");

    tarea.marcarNoCompletada(); // método de clase Tarea
  }

  tareasDelDia(fecha: Date): Tarea[] {
    return this.tareas.filter(t => fecha >= t.fechaInicio && fecha <= t.fechaFin);
  }

  horasAsignadasEnSemana(fecha: Date): number {
    const start = this.inicioSemana(fecha);
    const end = new Date(start);
    end.setDate(start.getDate() + 6);

    return this.tareas
      .filter(t => t.fechaInicio <= end && t.fechaFin >= start)
      .reduce((sum, t) => sum + t.duracionHoras, 0);
  }

  horasRestantesEnSemana(fecha: Date): number {
    return Math.max(0, Operario.LIMITE_SEMANAL_HORAS - this.horasAsignadasEnSemana(fecha));
  }

  private inicioSemana(fecha: Date): Date {
    const day = fecha.getDay();
    const diff = fecha.getDate() - day + (day === 0 ? -6 : 1); // lunes como inicio
    return new Date(fecha.getFullYear(), fecha.getMonth(), diff);
  }

  listarTareas(): Tarea[] {
    return this.tareas;
  }

  resumenDeHoras(fecha: Date): string {
    const horas = this.horasAsignadasEnSemana(fecha);
    return `🔔 A ${this.nombre} le quedan ${Operario.LIMITE_SEMANAL_HORAS - horas}h disponibles esta semana.`;
  }
}
