import { Empresa } from "../model/Empresa";
import { JefeOperaciones } from "../model/jefeOperaciones";
import { Maquinaria } from "../model/maquinaria";
import { SolicitudTarea } from "../model/solicitudTarea";

export class EmpresaService {
  constructor(private empresa: Empresa) {}

  agregarMaquinaria(maquina: Maquinaria): void {
    this.empresa.maquinaria.push(maquina);
  }

  listarMaquinariaDisponible(): Maquinaria[] {
    return this.empresa.maquinaria.filter(m => m.disponible);
  }

  agregarJefeOperaciones(jefe: JefeOperaciones): void {
    const existe = this.empresa.jefesOperaciones.some(j => j.id === jefe.id);
    if (!existe) {
      this.empresa.jefesOperaciones.push(jefe);
    }
  }

  recibirSolicitud(solicitud: SolicitudTarea): void {
    this.empresa.solicitudesPendientes.push(solicitud);
  }

  eliminarSolicitud(id: number): void {
    this.empresa.solicitudesPendientes = this.empresa.solicitudesPendientes.filter(s => s.id !== id);
  }

  solicitudesPendientes(): SolicitudTarea[] {
    return this.empresa.solicitudesPendientes;
  }
}
