import { Tarea } from "./tarea";
import { Usuario } from "./usuario";

export class Supervisor extends Usuario {
  tareasPorVerificar: Tarea[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'supervisor');
  }
}
