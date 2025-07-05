import { Usuario } from "./usuario";
import { SolicitudTarea } from "./solicitudTarea";

export class Gerente extends Usuario {
  solicitudesPendientes: SolicitudTarea[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente');
  }
}
