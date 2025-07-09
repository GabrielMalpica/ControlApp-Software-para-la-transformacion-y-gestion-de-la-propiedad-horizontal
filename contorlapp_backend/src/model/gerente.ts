import { Usuario } from "./usuario";

export class Gerente extends Usuario {

  constructor(id: number, nombre: string, correo: string, contrasena: string) {
    super(id, nombre, correo, 'gerente', contrasena);
  }
}
