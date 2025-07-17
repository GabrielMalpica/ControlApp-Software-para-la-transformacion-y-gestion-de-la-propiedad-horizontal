import { Empresa } from "../model/Empresa";
import { Tarea } from "../model/Tarea";
import { Insumo } from "../model/Insumo";
import { Conjunto } from "../model/Conjunto";
import { EstadoTarea } from "../model/enum/estadoTarea";

export class ReporteService {
  constructor(private empresa: Empresa) {}

  tareasAprobadasPorFecha(desde: Date, hasta: Date): Tarea[] {
    return this.empresa.tareasAprobadas.filter(t =>
      t.fechaVerificacion &&
      t.fechaVerificacion >= desde &&
      t.fechaVerificacion <= hasta
    );
  }

  tareasRechazadasPorFecha(desde: Date, hasta: Date): Tarea[] {
    return this.empresa.tareasRechazadas.filter(t =>
      t.fechaVerificacion &&
      t.fechaVerificacion >= desde &&
      t.fechaVerificacion <= hasta
    );
  }

  usoDeInsumosPorFecha(conjunto: Conjunto, desde: Date, hasta: Date): { insumo: Insumo; cantidad: number }[] {
    const filtrado = conjunto.inventario.consumos.filter(c =>
      c.fecha >= desde && c.fecha <= hasta
    );

    const resumen = new Map<number, { insumo: Insumo, cantidad: number }>();

    filtrado.forEach(({ insumo, cantidad }) => {
      const existente = resumen.get(insumo.id);
      if (existente) {
        existente.cantidad += cantidad;
      } else {
        resumen.set(insumo.id, { insumo, cantidad });
      }
    });

    return Array.from(resumen.values());
  }



  tareasPorEstado(
    conjunto: Conjunto,
    estado: EstadoTarea,
    desde: Date,
    hasta: Date
  ): Tarea[] {
    return conjunto.cronograma.filter(t =>
      t.estado === estado &&
      t.fechaInicio >= desde &&
      t.fechaFin <= hasta
    );
  }

  tareasConDetalle(
    conjunto: Conjunto,
    estado: EstadoTarea,
    desde: Date,
    hasta: Date
  ): { descripcion: string; ubicacion: string; elemento: string; responsable: string; estado: EstadoTarea }[] {
    return this.tareasPorEstado(conjunto, estado, desde, hasta).map(t => ({
      descripcion: t.descripcion,
      ubicacion: t.ubicacion.nombre,
      elemento: t.elemento.nombre,
      responsable: t.asignadoA.nombre,
      estado: t.estado
    }));
  }
}
