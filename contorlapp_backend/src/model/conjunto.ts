import { Administrador } from "./Administrador";
import { Inventario } from "./Inventario";
import { Maquinaria } from "./Maquinaria";
import { Operario } from "./Operario";
import { Tarea } from "./Tarea";
import { Ubicacion } from "./Ubicacion";

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
