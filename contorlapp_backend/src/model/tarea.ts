import { EstadoTarea } from "./enum/estadoTarea";

export class Tarea {
  id: number;
  descripcion: string;
  fechaInicio: Date;
  fechaFin: Date;
  fechaIniciarTarea?: Date;
  fechaFinalizarTarea?: Date;

  ubicacionId: number;
  elementoId: number;
  operarioId: number;

  duracionHoras: number;
  estado: EstadoTarea = EstadoTarea.ASIGNADA;
  insumosUsados: { insumoId: number; cantidad: number }[] = [];
  evidencias: string[] = [];

  verificadaPorId?: number;
  fechaVerificacion?: Date;
  observacionesRechazo?: string;

  constructor(
    id: number,
    descripcion: string,
    fechaInicio: Date,
    fechaFin: Date,
    ubicacionId: number,
    elementoId: number,
    duracionHoras: number,
    operarioId: number
  ) {
    this.id = id;
    this.descripcion = descripcion;
    this.fechaInicio = fechaInicio;
    this.fechaFin = fechaFin;
    this.ubicacionId = ubicacionId;
    this.elementoId = elementoId;
    this.duracionHoras = duracionHoras;
    this.operarioId = operarioId;
  }
}
