import { Gerente } from "./Gerente";

export class Empresa {
  nombre: string;
  nit: string;
  gerente?: Gerente;

  constructor(nombre: string, nit: string) {
    this.nombre = nombre;
    this.nit = nit;
  }
}
