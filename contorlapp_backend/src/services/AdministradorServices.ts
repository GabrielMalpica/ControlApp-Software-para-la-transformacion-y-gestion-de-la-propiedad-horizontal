import { Administrador } from "../model/administrador";
import { SolicitudTarea } from "../model/solicitudTarea";
import { Conjunto } from "../model/conjunto";
import { Ubicacion } from "../model/ubicacion";
import { Elemento } from "../model/elemento";

export class AdministradorService {
  constructor(private administrador: Administrador) {}

  solicitarTarea(
    id: number,
    descripcion: string,
    conjunto: Conjunto,
    ubicacion: Ubicacion,
    elemento: Elemento,
    duracionHoras: number
  ): SolicitudTarea {
    // En una versión futura puedes validar si el conjunto le pertenece al administrador
    return new SolicitudTarea(id, descripcion, conjunto, ubicacion, elemento, duracionHoras);
  }

  verConjuntos(): string[] {
    return this.administrador.listarConjuntos();
  }
}
