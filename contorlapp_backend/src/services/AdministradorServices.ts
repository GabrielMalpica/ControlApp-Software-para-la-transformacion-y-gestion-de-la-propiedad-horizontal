import { Administrador } from "../model/Administrador";
import { Conjunto } from "../model/Conjunto";
import { Ubicacion } from "../model/Ubicacion";
import { Elemento } from "../model/Elemento";
import { SolicitudTarea } from "../model/SolicitudTarea";
import { SolicitudInsumo } from "../model/SolicitudInsumo";
import { SolicitudMaquinaria } from "../model/SolicitudMaquinaria";
import { Insumo } from "../model/Insumo";
import { Maquinaria } from "../model/Maquinaria";
import { Operario } from "../model/Operario";

export class AdministradorService {
  constructor(private administrador: Administrador) {}

  verConjuntos(): string[] {
    return this.administrador.listarConjuntos();
  }

  solicitarTarea(id: number, descripcion: string, conjunto: Conjunto, ubicacion: Ubicacion, elemento: Elemento, duracionHoras: number): SolicitudTarea {
    return new SolicitudTarea(id, descripcion, conjunto, ubicacion, elemento, duracionHoras);
  }

  solicitarInsumos(
    id: number,
    insumos: { insumo: Insumo; cantidad: number }[],
    conjunto: Conjunto
  ): SolicitudInsumo {
    return new SolicitudInsumo(id, insumos, conjunto);
  }


  solicitarMaquinaria(id: number, conjunto: Conjunto, maquinaria: Maquinaria, responsable: Operario, fechaUso: Date, fechaDevolucion: Date): SolicitudMaquinaria {
    return new SolicitudMaquinaria(id, conjunto, maquinaria, responsable, fechaUso, fechaDevolucion);
  }
}
