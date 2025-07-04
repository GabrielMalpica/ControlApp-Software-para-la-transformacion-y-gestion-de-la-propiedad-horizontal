import { Administrador } from "./administrador";
import { Conjunto } from "./conjunto";
import { EstadoMaquinaria } from "./enum/estadoMaquinaria";
import { TipoFuncion } from "./enum/tipoFuncion";
import { TipoMaquinaria } from "./enum/tipoMaquinaria";
import { Insumo } from "./insumo";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";
import { Usuario } from "./usuario";

export class Gerente extends Usuario {
  stockMaquinaria: Maquinaria[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'gerente');
  }

  // Administradores
  crearAdministrador(id: number, nombre: string, correo: string): Administrador {
    return new Administrador(id, nombre, correo);
  }

  // Conjuntos
  crearConjunto(id: number, nombre: string, direccion: string, admin: Administrador, correo: String): Conjunto {
    return new Conjunto(id, nombre, direccion, admin, correo);
  }

  // Operarios
  crearOperario(id: number, nombre: string, correo: string, funciones: TipoFuncion[]): Operario {
    return new Operario(id, nombre, correo, funciones);
  }

  asignarOperarioAConjunto(operario: Operario, conjunto: Conjunto): void {
    conjunto.asignarOperario(operario);
  }

  // Insumos
  agregarInsumoAConjunto(conjunto: Conjunto, nombre: string, cantidad: number, unidad: string): void {
    const insumo = new Insumo(nombre, cantidad, unidad);
    conjunto.inventario.agregarInsumo(insumo);
  }

  // Maquinaria
  crearMaquinaria(nombre: string, marca: string, tipo: TipoMaquinaria): void {
    const id = this.stockMaquinaria.length + 1;
    const maquina = new Maquinaria(id, nombre, marca, tipo, EstadoMaquinaria.OPERATIVA, true);
    this.stockMaquinaria.push(maquina);
  }

  entregarMaquinariaAConjunto(nombre: string, conjunto: Conjunto): void {
    const maquina = this.stockMaquinaria.find(m => m.nombre === nombre && m.disponible);
    if (!maquina) throw new Error('Maquinaria no disponible u operativa');

    maquina.asignarAConjunto(conjunto);
    conjunto.agregarMaquinaria(maquina);

    this.stockMaquinaria = this.stockMaquinaria.filter(m => m !== maquina);
  }

  recibirMaquinariaDeConjunto(nombre: string, conjunto: Conjunto): void {
    const maquina = conjunto.entregarMaquinaria(nombre);
    if (!maquina) throw new Error('El conjunto no tiene esa maquinaria');

    maquina.devolver();
    this.stockMaquinaria.push(maquina);
  }

  // Consultas
  listarMaquinariaDisponible(): Maquinaria[] {
    return this.stockMaquinaria.filter(m => m.disponible);
  }

  maquinariaDisponible(id: number): boolean {
    const maquina = this.stockMaquinaria.find(m => m.id === id);
    return maquina !== undefined && maquina.disponible;
  }

}
