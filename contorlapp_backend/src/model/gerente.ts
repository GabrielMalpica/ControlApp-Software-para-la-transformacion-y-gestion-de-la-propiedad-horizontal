import { Usuario } from "./usuario";

export class Gerente extends Usuario {

  constructor(id: number, nombre: string, correo: string, contrasena: string, telefono: number, fechaNacimiento: Date) {
    super(id, nombre, correo, contrasena, 'gerente', telefono, fechaNacimiento);
  }
}
