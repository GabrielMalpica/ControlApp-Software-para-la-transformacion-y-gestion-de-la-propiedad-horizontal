export class Insumo {
  nombre: string;
  cantidad: number;
  unidad: string; // Ej: "litros", "kg", "botellas"

  constructor(nombre: string, cantidad: number, unidad: string) {
    this.nombre = nombre;
    this.cantidad = cantidad;
    this.unidad = unidad;
  }
}
