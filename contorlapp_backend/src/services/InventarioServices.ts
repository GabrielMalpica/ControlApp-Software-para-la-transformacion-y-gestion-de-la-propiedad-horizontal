import { Inventario } from "../model/inventario";
import { Insumo } from "../model/insumo";

export class InventarioService {
  constructor(private inventario: Inventario) {}

  agregarInsumo(insumo: Insumo): void {
    const existente = this.inventario.insumos.find(i => i.nombre === insumo.nombre && i.unidad === insumo.unidad);
    
    if (existente) {
      existente.cantidad += insumo.cantidad;
    } else {
      this.inventario.insumos.push(insumo);
    }
  }

  listarInsumos(): string[] {
    return this.inventario.insumos.map(i => `${i.nombre}: ${i.cantidad} ${i.unidad}`);
  }

  buscarInsumo(nombre: string): Insumo | undefined {
    return this.inventario.insumos.find(i => i.nombre === nombre);
  }

  eliminarInsumo(nombre: string): void {
    this.inventario.insumos = this.inventario.insumos.filter(i => i.nombre !== nombre);
  }

  consumirInsumo(nombre: string, cantidad: number): void {
    const insumo = this.inventario.insumos.find(i => i.nombre === nombre);
    if (!insumo) throw new Error(`El insumo "${nombre}" no existe.`);
    if (insumo.cantidad < cantidad) throw new Error(`Cantidad insuficiente de "${nombre}". Disponible: ${insumo.cantidad}`);

    insumo.cantidad -= cantidad;
  }
}
