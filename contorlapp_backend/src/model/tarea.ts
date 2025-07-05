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

  evidencias: string[] = [];
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
}
