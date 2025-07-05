import { Conjunto } from "./conjunto";
import { Tarea } from "./tarea";

export class Cronograma {
  conjunto: Conjunto;
  tareas: Tarea[] = [];

  constructor(conjunto: Conjunto) {
    this.conjunto = conjunto;
    // Carga todas las tareas del conjunto
    conjunto.operarios.forEach(op => {
      op.tareas.forEach(t => this.tareas.push(t));
    });
  }

  tareasPorOperario(operarioId: number): Tarea[] {
    return this.tareas.filter(t => t.asignadoA.id === operarioId);
  }

  tareasPorFecha(fecha: Date): Tarea[] {
    return this.tareas.filter(t =>
      t.fechaInicio <= fecha && fecha <= t.fechaFin
    );
  }

  tareasEnRango(fechaInicio: Date, fechaFin: Date): Tarea[] {
    return this.tareas.filter(t =>
      t.fechaFin >= fechaInicio && t.fechaInicio <= fechaFin
    );
  }

  tareasPorUbicacion(nombreUbicacion: string): Tarea[] {
    return this.tareas.filter(t =>
      t.ubicacion.nombre.toLowerCase() === nombreUbicacion.toLowerCase()
    );
  }

  tareasPorFiltro(opciones: {
    operarioId?: number;
    fechaExacta?: Date;
    fechaInicio?: Date;
    fechaFin?: Date;
    ubicacion?: string;
  }): Tarea[] {
    return this.tareas.filter(t => {
      const porOperario = !opciones.operarioId || t.asignadoA.id === opciones.operarioId;
      const porUbicacion = !opciones.ubicacion || t.ubicacion.nombre.toLowerCase() === opciones.ubicacion.toLowerCase();
      const porFechaExacta = !opciones.fechaExacta || (t.fechaInicio <= opciones.fechaExacta && opciones.fechaExacta <= t.fechaFin);
      const porRango = (!opciones.fechaInicio || t.fechaFin >= opciones.fechaInicio)
                    && (!opciones.fechaFin || t.fechaInicio <= opciones.fechaFin);

      return porOperario && porUbicacion && porFechaExacta && porRango;
    });
  }

  exportarComoEventosCalendario() {
    return this.tareas.map(t => ({
      title: `${t.descripcion} - ${t.asignadoA.nombre}`,
      start: t.fechaInicio.toISOString(),
      end: t.fechaFin.toISOString(),
      resource: {
        operario: t.asignadoA.nombre,
        ubicacion: t.ubicacion.nombre,
        elemento: t.elemento.nombre
      }
    }));
  }
}
