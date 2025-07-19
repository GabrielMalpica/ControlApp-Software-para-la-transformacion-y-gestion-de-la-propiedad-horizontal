import { Gerente } from "./Gerente";

export class Empresa {
  nombre: string;
  nit: string;
  gerente: Gerente;

  constructor(nombre: string, nit: string, gerente: Gerente) {
    this.nombre = nombre;
    this.nit = nit;
    this.gerente = gerente;
  }
}
