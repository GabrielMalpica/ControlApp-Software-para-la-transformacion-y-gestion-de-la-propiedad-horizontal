import { Administrador } from "../model/administrador";
import { Conjunto } from "../model/conjunto";
import { Maquinaria } from "../model/maquinaria";
import { Operario } from "../model/operario";
import { Tarea } from "../model/tarea";
import { Ubicacion } from "../model/ubicacion";

export class ConjuntoService {
  constructor(private conjunto: Conjunto) {}

  asignarOperario(operario: Operario): void {
    if (!this.conjunto.operarios.includes(operario)) {
      this.conjunto.operarios.push(operario);
    }

    if (!operario.conjuntos.includes(this.conjunto)) {
      operario.conjuntos.push(this.conjunto);
    }
  }

  asignarAdministrador(admin: Administrador): void {
    this.conjunto.administrador = admin;
    admin.agregarConjunto(this.conjunto);
  }

  eliminarAdministrador(): void {
    const adminActual = this.conjunto.administrador;
    if (!adminActual) return;

    adminActual.eliminarConjunto(this.conjunto);

    this.conjunto.administrador = null as any;
  }

  agregarMaquinaria(maquina: Maquinaria): void {
    this.conjunto.maquinariaPrestada.push(maquina);
  }

  entregarMaquinaria(nombre: string): Maquinaria | null {
    const maquina = this.conjunto.maquinariaPrestada.find(m => m.nombre === nombre);
    if (!maquina) return null;

    this.conjunto.maquinariaPrestada = this.conjunto.maquinariaPrestada.filter(m => m !== maquina);
    return maquina;
  }

  agregarUbicacion(ubicacion: Ubicacion): void {
    if (!this.conjunto.ubicaciones.some(u => u.nombre === ubicacion.nombre)) {
      this.conjunto.ubicaciones.push(ubicacion);
    }
  }

  buscarUbicacion(nombre: string): Ubicacion | undefined {
    return this.conjunto.ubicaciones.find(u => u.nombre === nombre);
  }

  agregarTareaACronograma(tarea: Tarea): void {
    this.conjunto.cronograma.push(tarea);
  }

  tareasPorFecha(fecha: Date): Tarea[] {
    return this.conjunto.cronograma.filter(t =>
      fecha >= t.fechaInicio && fecha <= t.fechaFin
    );
  }

  tareasPorOperario(operarioId: number): Tarea[] {
    return this.conjunto.cronograma.filter(t => t.asignadoA.id === operarioId);
  }

  tareasPorUbicacion(nombreUbicacion: string): Tarea[] {
    return this.conjunto.cronograma.filter(t => t.ubicacion.nombre === nombreUbicacion);
  }
}
