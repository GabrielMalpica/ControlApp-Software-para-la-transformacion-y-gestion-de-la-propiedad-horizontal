import { Administrador } from "./administrador";
import { Inventario } from "./inventario";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";
import { Tarea } from "./tarea";
import { Ubicacion } from "./ubicacion";

export class Conjunto {
  nit: number;
  nombre: string;
  direccion: string;
  correo: string;
  administrador: Administrador;
  operarios: Operario[] = [];
  inventario: Inventario;
  maquinariaPrestada: Maquinaria[] = [];
  ubicaciones: Ubicacion[] = [];
  cronograma: Tarea[] = [];

  constructor(nit: number, nombre: string, direccion: string, administrador: Administrador, correo: string) {
    this.nit = nit;
    this.nombre = nombre;
    this.direccion = direccion;
    this.correo = correo;
    this.administrador = administrador;
    this.inventario = new Inventario(this);
    administrador.agregarConjunto(this);
  }
}
