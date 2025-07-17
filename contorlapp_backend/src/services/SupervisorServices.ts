import { Supervisor } from "../model/Supervisor";
import { Tarea } from "../model/Tarea";
import { EstadoTarea } from "../model/enum/estadoTarea";
import { TareaService } from "./TareaServices";
import { Empresa } from "../model/Empresa";
import { SolicitudTarea } from "../model/SolicitudTarea";

export class SupervisorService {
  constructor(private supervisor: Supervisor, private empresa: Empresa) {}

  recibirTareaFinalizada(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("Solo se pueden verificar tareas completadas por el operario.");
    }
    this.supervisor.tareasPorVerificar.push(tarea);
  }

  aprobarTarea(tarea: Tarea): void {
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("No se puede aprobar una tarea que no está pendiente de aprobación.");
    }

    const tareaService = new TareaService(tarea);
    tareaService.aprobarTarea(this.supervisor);

    this.supervisor.tareasPorVerificar = this.supervisor.tareasPorVerificar.filter(t => t.id !== tarea.id);
    tarea.asignadoA.tareas = tarea.asignadoA.tareas.filter(t => t.id !== tarea.id);
    this.agregarTareaAprobada(tarea);
  }


  rechazarTarea(tarea: Tarea, observaciones: string): void {
    if (tarea.estado !== EstadoTarea.PENDIENTE_APROBACION) {
      throw new Error("No se puede rechazar una tarea que no está pendiente de aprobación.");
    }

    const tareaService = new TareaService(tarea);
    tareaService.rechazarTarea(this.supervisor, observaciones);

    this.supervisor.tareasPorVerificar = this.supervisor.tareasPorVerificar.filter(t => t.id !== tarea.id);
    tarea.asignadoA.tareas = tarea.asignadoA.tareas.filter(t => t.id !== tarea.id);

    const solicitudReabierta = new SolicitudTarea(
      tarea.id,
      tarea.descripcion,
      tarea.ubicacion.conjunto,
      tarea.ubicacion,
      tarea.elemento,
      tarea.duracionHoras
    );

    this.empresa.solicitudesTareas.push(solicitudReabierta);
    this.agregarTareaRechazada(tarea);
  }

  listarTareasPendientes(): Tarea[] {
    return this.supervisor.tareasPorVerificar;
  }

  agregarTareaAprobada(tarea: Tarea): void {
    this.empresa.tareasAprobadas.push(tarea);
  }

  agregarTareaRechazada(tarea: Tarea): void {
    this.empresa.tareasRechazadas.push(tarea);
  }

}