import { EstadoMaquinaria } from "./enum/estadoMaquinaria";
import { TipoMaquinaria } from "./enum/tipoMaquinaria";

export class Maquinaria {
  id: number;
  nombre: string;
  marca: string;
  tipo: TipoMaquinaria;
  estado: EstadoMaquinaria;
  disponible: boolean;
  asignadaAId?: number;
  fechaPrestamo?: Date;
  fechaDevolucionEstimada?: Date;
  responsableId?: number;

  constructor(
    id: number,
    nombre: string,
    marca: string,
    tipo: TipoMaquinaria,
    estado: EstadoMaquinaria = EstadoMaquinaria.OPERATIVA,
    disponible: boolean = true,
    asignadaAId?: number,
    fechaPrestamo?: Date,
    fechaDevolucionEstimada?: Date,
    responsableId?: number
  ) {
    this.id = id;
    this.nombre = nombre;
    this.marca = marca;
    this.tipo = tipo;
    this.estado = estado;
    this.disponible = disponible;
    this.asignadaAId = asignadaAId;
    this.fechaPrestamo = fechaPrestamo;
    this.fechaDevolucionEstimada = fechaDevolucionEstimada;
    this.responsableId = responsableId;
  }
}
