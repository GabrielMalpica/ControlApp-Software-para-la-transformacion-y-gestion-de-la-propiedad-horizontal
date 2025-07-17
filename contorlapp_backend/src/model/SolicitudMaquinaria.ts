import { ConjuntoService } from "../services/ConjuntoServices";
import { MaquinariaService } from "../services/MaquinariaServices";
import { Conjunto } from "./Conjunto";
import { Maquinaria } from "./Maquinaria";
import { Operario } from "./Operario";

export class SolicitudMaquinaria {
  id: number;
  conjunto: Conjunto;
  maquinaria: Maquinaria;
  responsable: Operario;
  fechaSolicitud: Date;
  fechaUso: Date;
  fechaDevolucionEstimada: Date;
  fechaAprobacion?: Date;
  aprobado: boolean = false;

  constructor(id: number, conjunto: Conjunto, maquinaria: Maquinaria, responsable: Operario, fechaUso: Date, fechaDevolucionEstimada: Date) {
    this.id = id;
    this.conjunto = conjunto;
    this.maquinaria = maquinaria;
    this.responsable = responsable;
    this.fechaUso = fechaUso;
    this.fechaDevolucionEstimada = fechaDevolucionEstimada;
    this.fechaSolicitud = new Date();
  }

  aprobar(): void {
    this.aprobado = true;
    this.fechaAprobacion = new Date();
    const conjuntoService = new ConjuntoService(this.conjunto);
    conjuntoService.agregarMaquinaria(this.maquinaria);
    const maquinariaService = new MaquinariaService(this.maquinaria)
    maquinariaService.asignarAConjunto(this.conjunto, this.diasDePrestamo(), this.responsable);
  }

  private diasDePrestamo(): number {
    const diff = this.fechaDevolucionEstimada.getTime() - this.fechaUso.getTime();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  }
}
