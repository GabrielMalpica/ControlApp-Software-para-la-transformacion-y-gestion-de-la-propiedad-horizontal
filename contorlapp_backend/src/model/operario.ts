import { Usuario } from "./usuario";
import { TipoFuncion } from "./enum/tipoFuncion";
import { Tarea } from "./tarea";
import { Conjunto } from "./conjunto";

export class Operario extends Usuario {
  funciones: TipoFuncion[];
  tareas: Tarea[] = [];
  conjuntos: Conjunto[] = [];
  static LIMITE_SEMANAL_HORAS = 46;

  constructor(id: number, nombre: string, correo: string, contrasena: string, funciones: TipoFuncion[]) {
    super(id, nombre, correo, 'operario', contrasena);
    this.funciones = funciones;
  }
}
