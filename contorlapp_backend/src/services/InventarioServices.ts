import { Insumo } from "../model/insumo";
import { Inventario } from "../model/inventario";

export class InventarioService {
  constructor(private inventario: Inventario) {}

  agregarInsumo(insumo: Insumo, cantidad: number): void {
    const existente = this.inventario.insumos.find(i => i.insumo.id === insumo.id);

    if (existente) {
      existente.cantidad += cantidad;
    } else {
      this.inventario.insumos.push({ insumo, cantidad });
    }
  }

  listarInsumos(): string[] {
    return this.inventario.insumos.map(
      i => `${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad}`
    );
  }


  eliminarInsumo(id: number): void {
    this.inventario.insumos = this.inventario.insumos.filter(i => i.insumo.id !== id);
  }

  buscarInsumoPorId(id: number): { insumo: Insumo; cantidad: number } | undefined {
    return this.inventario.insumos.find(item => item.insumo.id === id);
  }

  consumirInsumoPorId(id: number, cantidad: number): void {
    const entrada = this.buscarInsumoPorId(id);
    if (!entrada) throw new Error(`El insumo con ID "${id}" no existe.`);

    if (entrada.cantidad < cantidad) {
      throw new Error(`Cantidad insuficiente de "${entrada.insumo.nombre}". Disponible: ${entrada.cantidad}`);
    }

    entrada.cantidad -= cantidad;
  }

  listarInsumosBajos(umbral: number = 5): string[] {
    return this.inventario.insumos
      .filter(i => i.cantidad <= umbral)
      .map(i => `⚠️ ${i.insumo.nombre}: ${i.cantidad} ${i.insumo.unidad} (bajo stock)`);
  }

}
