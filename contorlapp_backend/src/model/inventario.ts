import { Conjunto } from "./conjunto";
import { Insumo } from "./insumo";

export class Inventario {
  conjunto: Conjunto;
  insumos: { insumo: Insumo; cantidad: number }[] = [];
  consumos: { insumo: Insumo; cantidad: number; fecha: Date }[] = [];

  constructor(conjunto: Conjunto) {
    this.conjunto = conjunto;
    this.insumos = [];
  }
}
