import { Insumo } from "./insumo";

export class Inventario {
  insumos: Insumo[] = [];

  agregarInsumo(insumo: Insumo): void {
    this.insumos.push(insumo);
  }

  listarInsumos(): string[] {
    return this.insumos.map(i => `${i.nombre}: ${i.cantidad} ${i.unidad}`);
  }

  buscarInsumo(nombre: string): Insumo | undefined {
    return this.insumos.find(i => i.nombre === nombre);
  }
}
