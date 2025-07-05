import { Tarea } from "./tarea";
import { Usuario } from "./usuario";
import { EstadoTarea } from "./enum/estadoTarea";

export class Supervisor extends Usuario {
  tareasPorVerificar: Tarea[] = [];

  constructor(id: number, nombre: string, correo: string) {
    super(id, nombre, correo, 'supervisor');
  }

  recibirTareaFinalizada(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("Solo se pueden verificar tareas completadas por el operario.");
    }
    this.tareasPorVerificar.push(tarea);
  }

  aprobarTarea(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("No se puede aprobar una tarea que no está marcada como completada.");
    }

    tarea.aprobarTarea(this); // método ya definido en clase Tarea
    this.tareasPorVerificar = this.tareasPorVerificar.filter(t => t.id !== tarea.id);
  }

  rechazarTarea(tarea: Tarea, observaciones: string): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("No se puede rechazar una tarea que no está marcada como completada.");
    }

    tarea.rechazarTarea(this, observaciones);
    this.tareasPorVerificar = this.tareasPorVerificar.filter(t => t.id !== tarea.id);
  }

  listarTareasPendientes(): Tarea[] {
    return this.tareasPorVerificar;
  }
}
