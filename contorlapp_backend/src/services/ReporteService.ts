// src/services/ReporteService.ts
import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";

/** Rangos básicos */
const RangoDTO = z
  .object({
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
  })
  .refine((d) => d.hasta >= d.desde, {
    path: ["hasta"],
    message: "hasta debe ser >= desde",
  });

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
        estado: EstadoTarea.APROBADA,
        fechaVerificacion: { gte: desde, lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operarios: true },
    });
  }

  async tareasRechazadasPorFecha(payload: unknown) {
    const { desde, hasta } = RangoDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        estado: EstadoTarea.RECHAZADA,
        fechaVerificacion: { gte: desde, lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operarios: true },
    });
  }

  /**
   * Resumen de insumos consumidos por fecha para un conjunto.
   * Devuelve: [{ insumoId, nombre, unidad, cantidad }]
   */
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

    const resumen = new Map<
      number,
      { insumoId: number; nombre: string; unidad: string; cantidad: number }
    >();

    for (const c of inventario.consumos) {
      const key = c.insumo.id;
      const prev = resumen.get(key);
      if (prev) {
        prev.cantidad += c.cantidad;
      } else {
        resumen.set(key, {
          insumoId: c.insumo.id,
          nombre: c.insumo.nombre,
          unidad: c.insumo.unidad,
          cantidad: c.cantidad,
        });
      }
    }
    return Array.from(resumen.values());
  }

  async tareasPorEstado(payload: unknown) {
    const { conjuntoId, estado, desde, hasta } =
      TareasPorEstadoDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        estado,
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      include: { ubicacion: true, elemento: true, operarios: true },
    });
  }

  async tareasConDetalle(payload: unknown) {
    const { conjuntoId, estado, desde, hasta } =
      TareasPorEstadoDTO.parse(payload);
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
        operarios: { include: { usuario: true } },
      },
    });

    return tareas.map((t) => {
      const nombresOperarios = t.operarios
        .map((op) => op.usuario?.nombre)
        .filter((n): n is string => Boolean(n));

      const responsables =
        nombresOperarios.length > 0
          ? nombresOperarios.join(", ")
          : "Sin asignar";

      return {
        descripcion: t.descripcion,
        ubicacion: t.ubicacion?.nombre ?? "Sin ubicación",
        elemento: t.elemento?.nombre ?? "Sin elemento",
        responsable: responsables,
        estado: t.estado,
      };
    });
  }
}
