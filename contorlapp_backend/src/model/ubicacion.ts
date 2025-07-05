import { Elemento } from "./elemento";

export class Ubicacion {
  nombre: string;
  elementos: Elemento[] = [];

  constructor(nombre: string) {
    this.nombre = nombre;
  }
}
