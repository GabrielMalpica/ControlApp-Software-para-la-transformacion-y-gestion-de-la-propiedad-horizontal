export class Usuario {
  id: number;
  nombre: string;
  correo: string;
  rol: string;

  constructor(id: number, nombre: string, correo: string, rol: string) {
    this.id = id;
    this.nombre = nombre;
    this.correo = correo;
    this.rol = rol;
  }

  cambiarCorreo(nuevoCorreo: string): void {
    this.correo = nuevoCorreo;
  }
}
