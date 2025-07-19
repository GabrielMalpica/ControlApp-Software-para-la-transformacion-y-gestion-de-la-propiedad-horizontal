export class Conjunto {
  nit: number;
  nombre: string;
  direccion: string;
  correo: string;
  administradorId?: number;

  constructor(
    nit: number,
    nombre: string,
    direccion: string,
    correo: string,
    administradorId?: number
  ) {
    this.nit = nit;
    this.nombre = nombre;
    this.direccion = direccion;
    this.correo = correo;
    this.administradorId = administradorId;
  }
}