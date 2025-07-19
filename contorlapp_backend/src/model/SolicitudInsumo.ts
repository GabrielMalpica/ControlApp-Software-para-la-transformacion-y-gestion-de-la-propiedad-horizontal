export class SolicitudInsumo {
  id: number;
  conjuntoId: number; // Relación por ID
  insumosSolicitados: { insumoId: number; cantidad: number }[];
  fechaSolicitud: Date;
  fechaAprobacion?: Date;
  aprobado: boolean = false;

  constructor(
    id: number,
    conjuntoId: number,
    insumosSolicitados: { insumoId: number; cantidad: number }[]
  ) {
    this.id = id;
    this.conjuntoId = conjuntoId;
    this.insumosSolicitados = insumosSolicitados;
    this.fechaSolicitud = new Date();
  }

  aprobar(fecha: Date = new Date()): void {
    this.aprobado = true;
    this.fechaAprobacion = fecha;
  }
}
