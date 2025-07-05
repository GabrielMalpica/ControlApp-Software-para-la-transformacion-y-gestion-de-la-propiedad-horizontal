import { Conjunto } from "./conjunto";
import { EstadoSolicitud } from "./enum/estadoSolicitud";

export class SolicitudTarea {
  id: number;
  descripcion: string;
  conjunto: Conjunto;
  ubicacion: string;
  elemento: string;
  duracionHoras: number;
  estado: EstadoSolicitud = EstadoSolicitud.PENDIENTE;
  observaciones?: string;

  constructor(
    id: number,
    descripcion: string,
    conjunto: Conjunto,
    ubicacion: string,
    elemento: string,
    duracionHoras: number
  ) {
    this.id = id;
    this.descripcion = descripcion;
    this.conjunto = conjunto;
    this.ubicacion = ubicacion;
    this.elemento = elemento;
    this.duracionHoras = duracionHoras;
  }

  aprobar(): void {
    this.estado = EstadoSolicitud.APROBADA;
  }

  rechazar(observacion: string): void {
    this.estado = EstadoSolicitud.RECHAZADA;
    this.observaciones = observacion;
  }
}