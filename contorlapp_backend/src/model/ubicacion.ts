import { Elemento } from "./elemento";

export class Ubicacion {
  nombre: string;
  elementos: Elemento[] = [];

  constructor(nombre: string) {
    this.nombre = nombre;
  }

  agregarElemento(elemento: Elemento): void {
    this.elementos.push(elemento);
  }

  listarElementos(): string[] {
    return this.elementos.map(e => e.nombre);
  }
}
