import { InventarioService } from "../services/InventarioServices";
import { Conjunto } from "./Conjunto";
import { Insumo } from "./Insumo";

export class SolicitudInsumo {
  id: number;
  insumos: { insumo: Insumo; cantidad: number }[];
  conjunto: Conjunto;
  fechaSolicitud: Date;
  fechaAprobacion?: Date;
  aprobado: boolean = false;

  constructor(id: number, insumos: { insumo: Insumo; cantidad: number }[], conjunto: Conjunto) {
    this.id = id;
    this.insumos = insumos;
    this.conjunto = conjunto;
    this.fechaSolicitud = new Date();
  }

  aprobar(): void {
    this.aprobado = true;
    this.fechaAprobacion = new Date();

    const inventarioService = new InventarioService(this.conjunto.inventario);
    this.insumos.forEach(({ insumo, cantidad }) => {
      inventarioService.agregarInsumo(insumo, cantidad);
    });
  }
}
