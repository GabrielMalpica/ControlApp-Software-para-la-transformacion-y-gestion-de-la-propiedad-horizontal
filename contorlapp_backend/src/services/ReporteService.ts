import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";

/** SIN extend: definimos el objeto completo y luego refine */
const RangoDTO = z
  .object({
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
  })
  .refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
  });

/** SIN extend: incluimos conjuntoId directamente en el objeto */
const RangoConConjuntoDTO = z
  .object({
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
    conjuntoId: z.string().min(1),
  })
  .refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
  });

/** SIN extend: agregamos estado directamente en el objeto */
const TareasPorEstadoDTO = z
  .object({
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
    conjuntoId: z.string().min(1),
    estado: z.nativeEnum(EstadoTarea),
  })
  .refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
  });

export class ReporteService {
  constructor(private prisma: PrismaClient) {}

  async tareasAprobadasPorFecha(payload: unknown) {
    const { desde, hasta } = RangoDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        estado: "APROBADA",
        fechaVerificacion: { gte: desde, lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operario: true },
    });
  }

  async tareasRechazadasPorFecha(payload: unknown) {
    const { desde, hasta } = RangoDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        estado: "RECHAZADA",
        fechaVerificacion: { gte: desde, lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operario: true },
    });
  }

  async usoDeInsumosPorFecha(payload: unknown) {
    const { conjuntoId, desde, hasta } = RangoConConjuntoDTO.parse(payload);
    const inventario = await this.prisma.inventario.findUnique({
      where: { conjuntoId },
      include: {
        consumos: {
          where: { fecha: { gte: desde, lte: hasta } },
          include: { insumo: true },
        },
      },
    });
    if (!inventario) throw new Error("Inventario no encontrado");

    const resumen = new Map<number, { insumo: any; cantidad: number }>();
    for (const consumo of inventario.consumos) {
      const ex = resumen.get(consumo.insumo.id);
      if (ex) ex.cantidad += consumo.cantidad;
      else resumen.set(consumo.insumo.id, { insumo: consumo.insumo, cantidad: consumo.cantidad });
    }
    return Array.from(resumen.values());
  }

  async tareasPorEstado(payload: unknown) {
    const { conjuntoId, estado, desde, hasta } = TareasPorEstadoDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado,
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operario: true },
    });
  }

  async tareasConDetalle(payload: unknown) {
    const { conjuntoId, estado, desde, hasta } = TareasPorEstadoDTO.parse(payload);
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado,
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      include: {
        ubicacion: true,
        elemento: true,
        operario: { include: { usuario: true } },
      },
    });

    return tareas.map((t) => ({
      descripcion: t.descripcion,
      ubicacion: t.ubicacion?.nombre ?? "Sin ubicación",
      elemento: t.elemento?.nombre ?? "Sin elemento",
      responsable: t.operario?.usuario?.nombre ?? "Sin asignar",
      estado: t.estado,
    }));
  }
}
