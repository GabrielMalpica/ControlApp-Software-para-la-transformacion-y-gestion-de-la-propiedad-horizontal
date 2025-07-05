import { SolicitudTarea } from "../model/solicitudTarea";
import { EstadoSolicitud } from "../model/enum/estadoSolicitud";

export class SolicitudTareaService {
  constructor(private solicitud: SolicitudTarea) {}

  aprobar(): void {
    if (this.solicitud.estado !== EstadoSolicitud.PENDIENTE) {
      throw new Error("❌ Solo se pueden aprobar solicitudes pendientes.");
    }
    this.solicitud.estado = EstadoSolicitud.APROBADA;
  }

  rechazar(observacion: string): void {
    if (this.solicitud.estado !== EstadoSolicitud.PENDIENTE) {
      throw new Error("❌ Solo se pueden rechazar solicitudes pendientes.");
    }
    this.solicitud.estado = EstadoSolicitud.RECHAZADA;
    this.solicitud.observaciones = observacion;
  }

  estadoActual(): string {
    return `📋 Estado de la solicitud: ${this.solicitud.estado}${this.solicitud.observaciones ? " - Obs: " + this.solicitud.observaciones : ""}`;
  }
}
