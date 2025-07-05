import { Elemento } from "./elemento";
import { Operario } from "./operario";
import { Ubicacion } from "./ubicacion";
import { Supervisor } from "./supervisor";
import { EstadoTarea } from "./enum/estadoTarea";

export class Tarea {
  id: number;
  descripcion: string;
  fechaInicio: Date;
  fechaFin: Date;
  ubicacion: Ubicacion;
  elemento: Elemento;
  duracionHoras: number;
  asignadoA: Operario;
  estado: EstadoTarea = EstadoTarea.ASIGNADA;

  evidencias: string[] = []; // rutas o nombres de archivos
  fechaCompletado?: Date;

  verificadaPor?: Supervisor;
  fechaVerificacion?: Date;
  observacionesRechazo?: string;

  constructor(
    id: number,
    descripcion: string,
    fechaInicio: Date,
    fechaFin: Date,
    ubicacion: Ubicacion,
    elemento: Elemento,
    duracionHoras: number,
    asignadoA: Operario
  ) {
    this.id = id;
    this.descripcion = descripcion;
    this.fechaInicio = fechaInicio;
    this.fechaFin = fechaFin;
    this.ubicacion = ubicacion;
    this.elemento = elemento;
    this.duracionHoras = duracionHoras;
    this.asignadoA = asignadoA;
  }

  agregarEvidencia(imagen: string): void {
    this.evidencias.push(imagen);
  }

  marcarComoCompletada(): void {
    this.estado = EstadoTarea.COMPLETADA;
    this.fechaCompletado = new Date();
  }

  marcarNoCompletada(): void {
    this.estado = EstadoTarea.NO_COMPLETADA;
  }

  aprobarTarea(supervisor: Supervisor): void {
    this.estado = EstadoTarea.APROBADA;
    this.verificadaPor = supervisor;
    this.fechaVerificacion = new Date();
  }

  rechazarTarea(supervisor: Supervisor, observacion: string): void {
    this.estado = EstadoTarea.RECHAZADA;
    this.verificadaPor = supervisor;
    this.fechaVerificacion = new Date();
    this.observacionesRechazo = observacion;
  }

  resumen(): string {
    return `📝 Tarea: ${this.descripcion}
👷 Operario: ${this.asignadoA.nombre}
📍 Ubicación: ${this.ubicacion.nombre}
🔧 Elemento: ${this.elemento.nombre}
🕒 Duración estimada: ${this.duracionHoras}h
📅 Del ${this.fechaInicio.toLocaleDateString()} al ${this.fechaFin.toLocaleDateString()}
📌 Estado actual: ${this.estado}`;
  }
}
