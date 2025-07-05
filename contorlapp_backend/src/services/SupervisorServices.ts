import { Supervisor } from "../model/supervisor";
import { Tarea } from "../model/tarea";
import { EstadoTarea } from "../model/enum/estadoTarea";
import { TareaService } from "./TareaServices";

export class SupervisorService {
  constructor(private supervisor: Supervisor) {}

  recibirTareaFinalizada(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("Solo se pueden verificar tareas completadas por el operario.");
    }
    this.supervisor.tareasPorVerificar.push(tarea);
  }

  aprobarTarea(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("No se puede aprobar una tarea que no está marcada como completada.");
    }

    const tareaService = new TareaService(tarea);

    tareaService.aprobarTarea(this.supervisor);
    this.supervisor.tareasPorVerificar = this.supervisor.tareasPorVerificar.filter(t => t.id !== tarea.id);
  }

  rechazarTarea(tarea: Tarea, observaciones: string): void {
    if (tarea.estado !== EstadoTarea.COMPLETADA) {
      throw new Error("No se puede rechazar una tarea que no está marcada como completada.");
    }

    const tareaService = new TareaService(tarea);

    tareaService.rechazarTarea(this.supervisor, observaciones);
    this.supervisor.tareasPorVerificar = this.supervisor.tareasPorVerificar.filter(t => t.id !== tarea.id);
  }

  listarTareasPendientes(): Tarea[] {
    return this.supervisor.tareasPorVerificar;
  }
}
