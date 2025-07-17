import { Elemento } from "./Elemento";
import { Operario } from "./Operario";
import { Supervisor } from "./Supervisor";
import { EstadoTarea } from "./enum/estadoTarea";
import { Ubicacion } from "./Ubicacion";

export class Tarea {
  id: number;
  descripcion: string;
  fechaInicio: Date;
  fechaFin: Date;
  fechaIniciarTarea?: Date;
  fechaFinalizarTarea?: Date;
  ubicacion: Ubicacion;
  elemento: Elemento;
  duracionHoras: number;
  asignadoA: Operario;
  estado: EstadoTarea = EstadoTarea.ASIGNADA;
  insumosUsados: { insumoId: number; cantidad: number }[] = [];

  evidencias: string[] = [];

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
