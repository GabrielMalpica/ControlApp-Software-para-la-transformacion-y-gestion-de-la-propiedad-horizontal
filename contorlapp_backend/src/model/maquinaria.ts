import { Conjunto } from "./conjunto";
import { EstadoMaquinaria } from "./enum/estadoMaquinaria";
import { TipoMaquinaria } from "./enum/tipoMaquinaria";

export class Maquinaria {
  id: number;
  nombre: string;
  marca: string;
  tipo: TipoMaquinaria;
  estado: EstadoMaquinaria;
  disponible: boolean;
  asignadaA?: Conjunto;
  fechaPrestamo?: Date;

  constructor(
    id: number,
    nombre: string,
    marca: string,
    tipo: TipoMaquinaria,
    estado: EstadoMaquinaria = EstadoMaquinaria.OPERATIVA,
    disponible: boolean = true
  ) {
    this.id = id;
    this.nombre = nombre;
    this.marca = marca;
    this.tipo = tipo;
    this.estado = estado;
    this.disponible = disponible;
  }

  asignarAConjunto(conjunto: Conjunto): void {
    this.asignadaA = conjunto;
    this.fechaPrestamo = new Date();
    this.disponible = false;
  }

  devolver(): void {
    this.asignadaA = undefined;
    this.fechaPrestamo = undefined;
    this.disponible = true;
  }
}
