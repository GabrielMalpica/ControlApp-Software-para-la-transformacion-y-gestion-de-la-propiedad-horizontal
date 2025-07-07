import { Empresa } from "../model/Empresa";
import { Insumo } from "../model/insumo";
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

  agregarInsumoAlCatalogo(insumo: Insumo): void {
    const existe = this.empresa.catalogoInsumos.some(i => i.nombre === insumo.nombre && i.unidad === insumo.unidad);
    if (existe) throw new Error("🚫 Ya existe un insumo con ese nombre y unidad");
    this.empresa.catalogoInsumos.push(insumo);
  }

  listarCatalogo(): string[] {
    return this.empresa.catalogoInsumos.map(i => i.toString());
  }

  buscarInsumoPorId(id: number): Insumo | undefined {
    return this.empresa.catalogoInsumos.find(i => i.id === id);
  }
}
