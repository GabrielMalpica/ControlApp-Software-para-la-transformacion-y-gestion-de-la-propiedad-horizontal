import { InventarioService } from "../services/InventarioServices";
import { Conjunto } from "./conjunto";
import { Insumo } from "./insumo";

export class SolicitudInsumo {
  id: number;
  insumos: Insumo[];
  conjunto: Conjunto;
  fechaSolicitud: Date;
  fechaAprobacion?: Date;
  aprobado: boolean = false;

  constructor(id: number, insumos: Insumo[], conjunto: Conjunto) {
    this.id = id;
    this.insumos = insumos;
    this.conjunto = conjunto;
    this.fechaSolicitud = new Date();
  }

  aprobar(): void {
    this.aprobado = true;
    this.fechaAprobacion = new Date();

    const inventarioService = new InventarioService(this.conjunto.inventario);
    this.insumos.forEach(i => inventarioService.agregarInsumo(i));
  }
}
