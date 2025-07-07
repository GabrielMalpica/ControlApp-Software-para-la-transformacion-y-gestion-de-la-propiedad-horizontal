export class Insumo {
  id: number;
  nombre: string;
  unidad: string;

  constructor(id: number, nombre: string, unidad: string) {
    this.id = id;
    this.nombre = nombre;
    this.unidad = unidad;
  }

  toString(): string {
    return `${this.nombre} (${this.unidad})`;
  }
}
