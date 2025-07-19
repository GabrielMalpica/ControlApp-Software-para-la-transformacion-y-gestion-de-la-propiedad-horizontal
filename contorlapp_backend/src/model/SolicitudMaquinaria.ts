export class SolicitudMaquinaria {
  id: number;
  conjuntoId: number;
  maquinariaId: number;
  responsableId: number;
  fechaSolicitud: Date;
  fechaUso: Date;
  fechaDevolucionEstimada: Date;
  fechaAprobacion?: Date;
  aprobado: boolean = false;

  constructor(
    id: number,
    conjuntoId: number,
    maquinariaId: number,
    responsableId: number,
    fechaUso: Date,
    fechaDevolucionEstimada: Date
  ) {
    this.id = id;
    this.conjuntoId = conjuntoId;
    this.maquinariaId = maquinariaId;
    this.responsableId = responsableId;
    this.fechaSolicitud = new Date();
    this.fechaUso = fechaUso;
    this.fechaDevolucionEstimada = fechaDevolucionEstimada;
  }

  aprobar(fecha: Date = new Date()): void {
    this.aprobado = true;
    this.fechaAprobacion = fecha;
  }

  diasDePrestamo(): number {
    const diff = this.fechaDevolucionEstimada.getTime() - this.fechaUso.getTime();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  }
}
