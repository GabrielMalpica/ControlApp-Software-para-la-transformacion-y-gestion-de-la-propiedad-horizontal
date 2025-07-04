import { Conjunto } from "./conjunto";
import { Usuario } from "./usuario";


export class Administrador extends Usuario {
  conjuntos: Conjunto[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'administrador');
  }
}
