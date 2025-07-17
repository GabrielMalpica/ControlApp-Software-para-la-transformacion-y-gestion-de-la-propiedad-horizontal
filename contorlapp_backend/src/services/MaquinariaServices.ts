import { Maquinaria } from "../model/Maquinaria";
import { Conjunto } from "../model/Conjunto";
import { Operario } from "../model/Operario";

export class MaquinariaService {
  constructor(private maquinaria: Maquinaria) {}

  asignarAConjunto(conjunto: Conjunto, diasPrestamo: number = 7, responsable?: Operario): void {
    this.maquinaria.asignadaA = conjunto;
    this.maquinaria.fechaPrestamo = new Date();
    this.maquinaria.fechaDevolucionEstimada = new Date(
      this.maquinaria.fechaPrestamo.getTime() + diasPrestamo * 24 * 60 * 60 * 1000
    );
    this.maquinaria.responsable = responsable;
    this.maquinaria.disponible = false;
  }

  devolver(): void {
    this.maquinaria.asignadaA = undefined;
    this.maquinaria.fechaPrestamo = undefined;
    this.maquinaria.fechaDevolucionEstimada = undefined;
    this.maquinaria.responsable = undefined;
    this.maquinaria.disponible = true;
  }

  estaDisponible(): boolean {
    return this.maquinaria.disponible;
  }

  obtenerResponsable(): string {
    return this.maquinaria.responsable?.nombre ?? "Sin asignar";
  }

  resumenEstado(): string {
    return `🛠️ ${this.maquinaria.nombre} (${this.maquinaria.marca}) - ${this.maquinaria.estado} - ${
      this.maquinaria.disponible ? "Disponible" : "Prestada"
    }`;
  }
}
