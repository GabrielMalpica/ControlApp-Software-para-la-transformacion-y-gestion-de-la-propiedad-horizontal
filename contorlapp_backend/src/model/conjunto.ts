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
  administrador?: Administrador; // ← ahora es opcional
  operarios: Operario[] = [];
  inventario: Inventario;
  maquinariaPrestada: Maquinaria[] = [];
  ubicaciones: Ubicacion[] = [];
  cronograma: Tarea[] = [];

  constructor(
    nit: number,
    nombre: string,
    direccion: string,
    correo: string,
    administrador?: Administrador
  ) {
    this.nit = nit;
    this.nombre = nombre;
    this.direccion = direccion;
    this.correo = correo;
    this.inventario = new Inventario(this);

    if (administrador) {
      this.administrador = administrador;
      administrador.agregarConjunto(this);
    }
  }
}
