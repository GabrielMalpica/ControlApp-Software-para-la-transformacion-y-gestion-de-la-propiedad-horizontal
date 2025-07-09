export class Usuario {
  id: number;
  nombre: string;
  correo: string;
  contrasena: string;
  rol: string;

  constructor(id: number, nombre: string, correo: string, contrasena: string, rol: string) {
    this.id = id;
    this.nombre = nombre;
    this.correo = correo;
    this.contrasena = contrasena;
    this.rol = rol;
  }

  cambiarCorreo(nuevoCorreo: string): void {
    this.correo = nuevoCorreo;
  }
}
