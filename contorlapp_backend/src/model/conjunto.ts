import { Administrador } from "./administrador";
import { Inventario } from "./inventario";
import { Maquinaria } from "./maquinaria";
import { Operario } from "./operario";
import { Tarea } from "./tarea";
import { Ubicacion } from "./ubicacion";

export class Conjunto {
  id: number;
  nombre: string;
  direccion: string;
  correo: string;
  administrador: Administrador;
  operarios: Operario[] = [];
  inventario: Inventario;
  maquinariaPrestada: Maquinaria[] = [];
  ubicaciones: Ubicacion[] = [];
  cronograma: Tarea[] = [];

  constructor(id: number, nombre: string, direccion: string, administrador: Administrador, correo: string) {
    this.id = id;
    this.nombre = nombre;
    this.direccion = direccion;
    this.correo = correo;
    this.administrador = administrador;
    this.inventario = new Inventario();

    administrador.agregarConjunto(this);
  }

  // ─── OPERARIOS ─────────────────────────────────────────────
  asignarOperario(operario: Operario): void {
    if (!this.operarios.includes(operario)) {
      this.operarios.push(operario);
    }
  }

  // ─── MAQUINARIA ────────────────────────────────────────────
  agregarMaquinaria(maquina: Maquinaria): void {
    this.maquinariaPrestada.push(maquina);
  }

  entregarMaquinaria(nombre: string): Maquinaria | null {
    const maquina = this.maquinariaPrestada.find(m => m.nombre === nombre);
    if (!maquina) return null;

    this.maquinariaPrestada = this.maquinariaPrestada.filter(m => m !== maquina);
    return maquina;
  }

  // ─── UBICACIONES ───────────────────────────────────────────
  agregarUbicacion(ubicacion: Ubicacion): void {
    if (!this.ubicaciones.some(u => u.nombre === ubicacion.nombre)) {
      this.ubicaciones.push(ubicacion);
    }
  }

  buscarUbicacion(nombre: string): Ubicacion | undefined {
    return this.ubicaciones.find(u => u.nombre === nombre);
  }

  // ─── CRONOGRAMA ────────────────────────────────────────────
  agregarTareaACronograma(tarea: Tarea): void {
    this.cronograma.push(tarea);
  }

  tareasPorFecha(fecha: Date): Tarea[] {
    return this.cronograma.filter(t =>
      fecha >= t.fechaInicio && fecha <= t.fechaFin
    );
  }

  tareasPorOperario(operarioId: number): Tarea[] {
    return this.cronograma.filter(t => t.asignadoA.id === operarioId);
  }

  tareasPorUbicacion(nombreUbicacion: string): Tarea[] {
    return this.cronograma.filter(t => t.ubicacion.nombre === nombreUbicacion);
  }
}