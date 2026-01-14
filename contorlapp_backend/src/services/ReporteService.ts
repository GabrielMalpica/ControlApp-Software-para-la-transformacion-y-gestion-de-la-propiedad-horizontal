// src/services/ReporteService.ts
import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";
import { decToNumber } from "../utils/decimal";

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
      select: { id: true },
    });
    if (!inventario) throw new Error("Inventario no encontrado");

    const rows = await this.prisma.consumoInsumo.groupBy({
      by: ["insumoId"],
      where: {
        inventarioId: inventario.id,
        fecha: { gte: desde, lte: hasta },
      },
      _sum: { cantidad: true },
    });

    const insumos = await this.prisma.insumo.findMany({
      where: { id: { in: rows.map((r) => r.insumoId) } },
      select: { id: true, nombre: true, unidad: true },
    });

    const mapInfo = new Map(insumos.map((i) => [i.id, i]));

    return rows.map((r) => {
      const info = mapInfo.get(r.insumoId)!;
      return {
        insumoId: r.insumoId,
        nombre: info.nombre,
        unidad: info.unidad,
        cantidad: decToNumber(r._sum.cantidad),
      };
    });
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
