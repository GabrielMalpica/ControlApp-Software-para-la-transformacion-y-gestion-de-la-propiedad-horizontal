import { Conjunto } from "./conjunto";
import { Elemento } from "./elemento";
import { EstadoSolicitud } from "./enum/estadoSolicitud";
import { Ubicacion } from "./ubicacion";

export class SolicitudTarea {
  id: number;
  descripcion: string;
  conjunto: Conjunto;
  ubicacion: Ubicacion;
  elemento: Elemento;
  duracionHoras: number;
  estado: EstadoSolicitud = EstadoSolicitud.PENDIENTE;
  observaciones?: string;

  constructor(
    id: number,
    descripcion: string,
    conjunto: Conjunto,
    ubicacion: Ubicacion,
    elemento: Elemento,
    duracionHoras: number
  ) {
    this.id = id;
    this.descripcion = descripcion;
    this.conjunto = conjunto;
    this.ubicacion = ubicacion;
    this.elemento = elemento;
    this.duracionHoras = duracionHoras;
  }
}
