import { Conjunto } from "./conjunto";
import { Usuario } from "./usuario";

export class Administrador extends Usuario {
  conjuntos: Conjunto[] = [];

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


  agregarConjunto(conjunto: Conjunto): void {
    if (!this.conjuntos.includes(conjunto)) {
      this.conjuntos.push(conjunto);
    }
  }

  eliminarConjunto(conjunto: Conjunto): void {
    this.conjuntos = this.conjuntos.filter(c => c !== conjunto);
  }

  listarConjuntos(): string[] {
    return this.conjuntos.map(c => c.nombre + ' ' + c.nit);
  }
}
