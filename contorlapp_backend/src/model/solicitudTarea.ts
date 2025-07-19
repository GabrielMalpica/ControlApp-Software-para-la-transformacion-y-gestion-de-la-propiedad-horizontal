import { EstadoSolicitud } from "./enum/estadoSolicitud";

export class SolicitudTarea {
  id: number;
  descripcion: string;
  conjuntoId: number;
  ubicacionId: number;
  elementoId: number;
  duracionHoras: number;
  estado: EstadoSolicitud = EstadoSolicitud.PENDIENTE;
  observaciones?: string;

  constructor(
    id: number,
    descripcion: string,
    conjuntoId: number,
    ubicacionId: number,
    elementoId: number,
    duracionHoras: number
  ) {
    this.id = id;
    this.descripcion = descripcion;
    this.conjuntoId = conjuntoId;
    this.ubicacionId = ubicacionId;
    this.elementoId = elementoId;
    this.duracionHoras = duracionHoras;
  }

  agregarObservaciones(obs: string) {
    this.observaciones = obs;
  }

  aprobar() {
    this.estado = EstadoSolicitud.APROBADA;
  }

  rechazar(obs: string) {
    this.estado = EstadoSolicitud.RECHAZADA;
    this.observaciones = obs;
  }
}