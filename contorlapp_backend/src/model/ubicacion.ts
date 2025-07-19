import { Conjunto } from "./Conjunto";

export class Ubicacion {
  conjunto: Conjunto;
  nombre: string;

  constructor(nombre: string, conjunto: Conjunto) {
    this.nombre = nombre;
    this.conjunto = conjunto;
  }
}
