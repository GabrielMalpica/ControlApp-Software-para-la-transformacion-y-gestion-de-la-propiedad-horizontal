import { Tarea } from "../model/tarea";
import { Supervisor } from "../model/supervisor";
import { EstadoTarea } from "../model/enum/estadoTarea";
import { InventarioService } from "./InventarioServices";

export class TareaService {
  constructor(private tarea: Tarea) {}

  agregarEvidencia(imagen: string): void {
    this.tarea.evidencias.push(imagen);
  }

  iniciarTarea(): void {
    if (this.tarea.estado !== EstadoTarea.ASIGNADA) {
      throw new Error("Solo se puede iniciar una tarea que esté asignada.");
    }
    this.tarea.estado = EstadoTarea.EN_PROCESO;
    this.tarea.fechaIniciarTarea = new Date();
  }



  marcarComoCompletadaConInsumos(
    insumosUsados: { insumoId: number; cantidad: number }[],
    inventarioService: InventarioService
  ): void {
    insumosUsados.forEach(({ insumoId, cantidad }) => {
      inventarioService.consumirInsumoPorId(insumoId, cantidad);
    });

    this.tarea.insumosUsados = insumosUsados;
    this.tarea.estado = EstadoTarea.PENDIENTE_APROBACION;
    this.tarea.fechaFinalizarTarea = new Date();
  }


  marcarNoCompletada(): void {
    this.tarea.estado = EstadoTarea.NO_COMPLETADA;
  }

  aprobarTarea(supervisor: Supervisor): void {
    this.tarea.estado = EstadoTarea.APROBADA;
    this.tarea.verificadaPor = supervisor;
    this.tarea.fechaVerificacion = new Date();
  }

  rechazarTarea(supervisor: Supervisor, observacion: string): void {
    this.tarea.estado = EstadoTarea.RECHAZADA;
    this.tarea.verificadaPor = supervisor;
    this.tarea.fechaVerificacion = new Date();
    this.tarea.observacionesRechazo = observacion;
  }

  resumen(): string {
    return `📝 Tarea: ${this.tarea.descripcion}
    👷 Operario: ${this.tarea.asignadoA.nombre}
    📍 Ubicación: ${this.tarea.ubicacion.nombre}
    🔧 Elemento: ${this.tarea.elemento.nombre}
    🕒 Duración estimada: ${this.tarea.duracionHoras}h
    📅 Del ${this.tarea.fechaInicio.toLocaleDateString()} al ${this.tarea.fechaFin.toLocaleDateString()}
    📌 Estado actual: ${this.tarea.estado}`;
  }
}
