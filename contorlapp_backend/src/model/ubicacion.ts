import { Conjunto } from "./Conjunto";
import { Elemento } from "./Elemento";

export class Ubicacion {
  conjunto: Conjunto;
  nombre: string;
  elementos: Elemento[] = [];

  constructor(nombre: string, conjunto: Conjunto) {
    this.nombre = nombre;
    this.conjunto = conjunto;
    conjunto.ubicaciones.push(this);
  }
}
