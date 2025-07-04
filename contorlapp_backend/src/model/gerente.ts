import { Maquinaria } from "./maquinaria";
import { Usuario } from "./usuario";

export class Gerente extends Usuario {
  stockMaquinaria: Maquinaria[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente');
  }

}
