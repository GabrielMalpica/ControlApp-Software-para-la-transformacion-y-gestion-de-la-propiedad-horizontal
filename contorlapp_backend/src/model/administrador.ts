import { Conjunto } from "./conjunto";
import { Usuario } from "./usuario";

export class Administrador extends Usuario {
  conjuntos: Conjunto[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'administrador');
  }

  agregarConjunto(conjunto: Conjunto): void {
    if (!this.conjuntos.includes(conjunto)) {
      this.conjuntos.push(conjunto);
    }
  }

  listarConjuntos(): string[] {
    return this.conjuntos.map(c => c.nombre + ' ' + c.nit);
  }
}
