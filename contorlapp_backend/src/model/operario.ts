import { Usuario } from "./usuario";
import { TipoFuncion } from "./enum/tipoFuncion";
import { Tarea } from "./tarea";

export class Operario extends Usuario {
  funciones: TipoFuncion[];
  tareas: Tarea[] = [];
  static LIMITE_SEMANAL_HORAS = 46;

  constructor(id: number, nombre: string, correo: string, funciones: TipoFuncion[]) {
    super(id, nombre, correo, 'operario');
    this.funciones = funciones;
  }
}
