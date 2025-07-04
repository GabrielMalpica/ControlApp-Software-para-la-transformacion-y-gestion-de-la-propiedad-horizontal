import { Usuario } from "./usuario";

export class Gerente extends Usuario {
  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente'); // Se asigna el rol directamente
  }

  crearConjunto(nombreConjunto: string): string {
    return `El gerente ${this.nombre} ha creado el conjunto ${nombreConjunto}.`;
  }

  asignarJefeOperaciones(nombreJefe: string, conjunto: string): string {
    return `Se asignó a ${nombreJefe} como jefe de operaciones del conjunto ${conjunto}.`;
  }
}
