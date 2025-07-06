import { Administrador } from "../model/administrador";
import { Conjunto } from "../model/conjunto";
import { Ubicacion } from "../model/ubicacion";
import { Elemento } from "../model/elemento";
import { SolicitudTarea } from "../model/solicitudTarea";
import { SolicitudInsumo } from "../model/solicitudInsumo";
import { SolicitudMaquinaria } from "../model/SolicitudMaquinaria";
import { Insumo } from "../model/insumo";
import { Maquinaria } from "../model/maquinaria";
import { Operario } from "../model/operario";

export class AdministradorService {
  constructor(private administrador: Administrador) {}

  verConjuntos(): string[] {
    return this.administrador.listarConjuntos();
  }

  solicitarTarea(id: number, descripcion: string, conjunto: Conjunto, ubicacion: Ubicacion, elemento: Elemento, duracionHoras: number): SolicitudTarea {
    return new SolicitudTarea(id, descripcion, conjunto, ubicacion, elemento, duracionHoras);
  }

  solicitarInsumos(id: number, insumos: Insumo[], conjunto: Conjunto): SolicitudInsumo {
    return new SolicitudInsumo(id, insumos, conjunto);
  }

  solicitarMaquinaria(id: number, conjunto: Conjunto, maquinaria: Maquinaria, responsable: Operario, fechaUso: Date, fechaDevolucion: Date): SolicitudMaquinaria {
    return new SolicitudMaquinaria(id, conjunto, maquinaria, responsable, fechaUso, fechaDevolucion);
  }
}
