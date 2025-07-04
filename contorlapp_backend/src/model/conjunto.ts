import { Administrador } from "./administrador";

export class Conjunto {
  id: number;
  nombre: string;
  direccion: string;
  administrador: Administrador;

  constructor(id: number, nombre: string, direccion: string, administrador: Administrador) {
    this.id = id;
    this.nombre = nombre;
    this.direccion = direccion;
    this.administrador = administrador;

  }
}
