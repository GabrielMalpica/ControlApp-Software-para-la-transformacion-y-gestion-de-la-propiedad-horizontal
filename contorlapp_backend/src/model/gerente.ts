import { Usuario } from "./usuario";

export class Gerente extends Usuario {
  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente');
  }

  crearConjunto(nombreConjunto: string): void {
    
  }
}
