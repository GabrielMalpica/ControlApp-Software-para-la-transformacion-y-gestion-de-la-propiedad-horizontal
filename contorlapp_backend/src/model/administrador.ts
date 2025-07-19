import { Usuario } from "./Usuario";

export class Administrador extends Usuario {

  constructor(
    id: number,
    nombre: string,
    correo: string,
    contrasena: string,
    telefono: number,
    fechaNacimiento: Date
  ) {
    super(id, nombre, correo, contrasena, 'administrador', telefono, fechaNacimiento);
  }
}
