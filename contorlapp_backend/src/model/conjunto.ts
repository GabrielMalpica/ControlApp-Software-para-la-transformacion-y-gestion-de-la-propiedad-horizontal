import { Administrador } from "./administrador";
import { Inventario } from "./inventario";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";

export class Conjunto {
  id: number;
  nombre: string;
  direccion: string;
  administrador: Administrador;
  operarios: Operario[] = [];
  inventario: Inventario;
  maquinariaPrestada: Maquinaria[] = [];

  constructor(id: number, nombre: string, direccion: string, administrador: Administrador) {
    this.id = id;
    this.nombre = nombre;
    this.direccion = direccion;
    this.administrador = administrador;
    this.inventario = new Inventario();
    administrador.agregarConjunto(this);
  }

  asignarOperario(operario: Operario): void {
    this.operarios.push(operario);
  }

  agregarMaquinaria(maquina: Maquinaria): void {
    this.maquinariaPrestada.push(maquina);
  }

  entregarMaquinaria(nombre: string): Maquinaria | null {
    const maquina = this.maquinariaPrestada.find(m => m.nombre === nombre);
    if (!maquina) return null;

    this.maquinariaPrestada = this.maquinariaPrestada.filter(m => m !== maquina);
    return maquina;
  }
}
