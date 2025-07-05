import { Tarea } from "../model/tarea";
import { Supervisor } from "../model/supervisor";
import { EstadoTarea } from "../model/enum/estadoTarea";

export class TareaService {
  constructor(private tarea: Tarea) {}

  agregarEvidencia(imagen: string): void {
    this.tarea.evidencias.push(imagen);
  }

  marcarComoCompletada(): void {
    this.tarea.estado = EstadoTarea.COMPLETADA;
    this.tarea.fechaCompletado = new Date();
  }

  marcarNoCompletada(): void {
    this.tarea.estado = EstadoTarea.NO_COMPLETADA;
  }

  aprobarTarea(supervisor: Supervisor): void {
    this.tarea.estado = EstadoTarea.APROBADA;
    this.tarea.verificadaPor = supervisor;
    this.tarea.fechaVerificacion = new Date();
  }

  rechazarTarea(supervisor: Supervisor, observacion: string): void {
    this.tarea.estado = EstadoTarea.RECHAZADA;
    this.tarea.verificadaPor = supervisor;
    this.tarea.fechaVerificacion = new Date();
    this.tarea.observacionesRechazo = observacion;
  }

  resumen(): string {
    return `📝 Tarea: ${this.tarea.descripcion}
    👷 Operario: ${this.tarea.asignadoA.nombre}
    📍 Ubicación: ${this.tarea.ubicacion.nombre}
    🔧 Elemento: ${this.tarea.elemento.nombre}
    🕒 Duración estimada: ${this.tarea.duracionHoras}h
    📅 Del ${this.tarea.fechaInicio.toLocaleDateString()} al ${this.tarea.fechaFin.toLocaleDateString()}
    📌 Estado actual: ${this.tarea.estado}`;
  }
}
