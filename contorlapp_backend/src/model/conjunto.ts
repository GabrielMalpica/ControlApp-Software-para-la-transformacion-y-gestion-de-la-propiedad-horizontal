import { Administrador } from "./administrador";
import { Inventario } from "./inventario";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";
import { Tarea } from "./tarea";
import { Ubicacion } from "./ubicacion";

export class Conjunto {
  id: number;
  nombre: string;
  direccion: string;
  correo: string;
  administrador: Administrador;
  operarios: Operario[] = [];
  inventario: Inventario;
  maquinariaPrestada: Maquinaria[] = [];
  ubicaciones: Ubicacion[] = [];
  cronograma: Tarea[] = [];

  constructor(id: number, nombre: string, direccion: string, administrador: Administrador, correo: string) {
    this.id = id;
    this.nombre = nombre;
    this.direccion = direccion;
    this.correo = correo;
    this.administrador = administrador;
    this.inventario = new Inventario();
    administrador.agregarConjunto(this);
  }
}
