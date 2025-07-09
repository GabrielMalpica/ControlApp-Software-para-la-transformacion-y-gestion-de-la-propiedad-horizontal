import { Usuario } from "./usuario";

export class JefeOperaciones extends Usuario{
    constructor(id: number, nombre: string, correo: string, contrasena: string) {
    super(id, nombre, correo, 'jefe-operaciones', contrasena);
  }
}