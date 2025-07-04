import { Usuario } from "./usuario";

export class Supervisor extends Usuario{
    constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'supervisor');
  }
}