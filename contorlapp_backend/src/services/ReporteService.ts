import { Empresa } from "../model/Empresa";
import { Tarea } from "../model/tarea";
import { Insumo } from "../model/insumo";

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

  usoDeInsumosPorFecha(desde: Date, hasta: Date): { insumo: Insumo; cantidad: number }[] {
    const filtrado = this.empresa.insumosConsumidos.filter(i =>
      i.fecha >= desde && i.fecha <= hasta
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
}
