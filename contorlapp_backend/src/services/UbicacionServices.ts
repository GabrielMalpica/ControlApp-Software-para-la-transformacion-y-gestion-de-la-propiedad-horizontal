import { Ubicacion } from "../model/ubicacion";
import { Elemento } from "../model/elemento";

export class UbicacionService {
  constructor(private ubicacion: Ubicacion) {}

  agregarElemento(elemento: Elemento): void {
    this.ubicacion.elementos.push(elemento);
  }

  listarElementos(): string[] {
    return this.ubicacion.elementos.map(e => e.nombre);
  }

  buscarElementoPorNombre(nombre: string): Elemento | undefined {
    return this.ubicacion.elementos.find(e => e.nombre.toLowerCase() === nombre.toLowerCase());
  }
}
