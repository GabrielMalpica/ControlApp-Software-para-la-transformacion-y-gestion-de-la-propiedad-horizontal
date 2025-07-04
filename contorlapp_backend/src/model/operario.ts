import { TipoFuncion } from "./roles/tipoFuncion";
import { Usuario } from "./usuario";

export class Operario extends Usuario{
    funciones: TipoFuncion[];

    constructor(id: number, nombre: string, correo: string, funciones: TipoFuncion[]) {
    super(id, nombre, correo, 'operario');
    this.funciones = funciones;
  }

  
}