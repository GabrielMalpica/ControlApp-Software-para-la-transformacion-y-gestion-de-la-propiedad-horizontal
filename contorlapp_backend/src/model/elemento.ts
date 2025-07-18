import { Ubicacion } from "./Ubicacion";

export class Elemento {
  ubicacion: Ubicacion;
  nombre: string;

  constructor(ubicacion: Ubicacion, nombre: string) {
    this.ubicacion = ubicacion;
    this.nombre = nombre;

    ubicacion.agregarElemento(this);
  }
}
