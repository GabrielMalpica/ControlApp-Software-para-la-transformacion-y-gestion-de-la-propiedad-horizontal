import { Conjunto } from "./conjunto";
import { EstadoMaquinaria } from "./enum/estadoMaquinaria";
import { TipoMaquinaria } from "./enum/tipoMaquinaria";
import { Operario } from "./operario";

export class Maquinaria {
  id: number;
  nombre: string;
  marca: string;
  tipo: TipoMaquinaria;
  estado: EstadoMaquinaria;
  disponible: boolean;
  asignadaA?: Conjunto;
  fechaPrestamo?: Date;
  fechaDevolucionEstimada?: Date;
  responsable?: Operario;

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
}
