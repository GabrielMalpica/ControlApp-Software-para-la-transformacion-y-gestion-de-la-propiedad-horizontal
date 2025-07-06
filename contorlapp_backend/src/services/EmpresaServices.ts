import { Empresa } from "../model/Empresa";
import { JefeOperaciones } from "../model/jefeOperaciones";
import { Maquinaria } from "../model/maquinaria";
import { SolicitudTarea } from "../model/solicitudTarea";

export class EmpresaService {
  constructor(private empresa: Empresa) {}

  agregarMaquinaria(maquina: Maquinaria): void {
    this.empresa.stockMaquinaria.push(maquina);
  }

  listarMaquinariaDisponible(): Maquinaria[] {
    return this.empresa.stockMaquinaria.filter(m => m.disponible);
  }

  obtenerMaquinariaDisponible(): Maquinaria[] {
    return this.empresa.stockMaquinaria.filter(m => m.disponible);
  }

  obtenerMaquinariaPrestada(): {
    maquina: Maquinaria;
    conjunto: string;
    responsable: string;
    fechaPrestamo: Date;
    fechaDevolucionEstimada?: Date;
  }[] {
    return this.empresa.stockMaquinaria
      .filter(m => !m.disponible && m.asignadaA)
      .map(m => ({
        maquina: m,
        conjunto: m.asignadaA?.nombre ?? "Desconocido",
        responsable: m.responsable?.nombre ?? "Sin asignar",
        fechaPrestamo: m.fechaPrestamo!,
        fechaDevolucionEstimada: m.fechaDevolucionEstimada
      }));
  }

  agregarJefeOperaciones(jefe: JefeOperaciones): void {
    const existe = this.empresa.jefesOperaciones.some(j => j.id === jefe.id);
    if (!existe) {
      this.empresa.jefesOperaciones.push(jefe);
    }
  }

  recibirSolicitud(solicitud: SolicitudTarea): void {
    this.empresa.solicitudesTareas.push(solicitud);
  }

  eliminarSolicitud(id: number): void {
    this.empresa.solicitudesTareas = this.empresa.solicitudesTareas.filter(s => s.id !== id);
  }

  solicitudesPendientes(): SolicitudTarea[] {
    return this.empresa.solicitudesTareas;
  }
}
