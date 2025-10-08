import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

// DTOs locales de filtros para este servicio
const OperarioIdDTO = z.object({ operarioId: z.number().int().positive() });
const FechaDTO = z.object({ fecha: z.coerce.date() });
const RangoFechasDTO = z.object({
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
}).refine((d) => d.fechaFin >= d.fechaInicio, {
  message: "fechaFin debe ser mayor o igual a fechaInicio",
  path: ["fechaFin"],
});

const TareasPorFiltroDTO = z.object({
  operarioId: z.number().int().positive().optional(),
  fechaExacta: z.coerce.date().optional(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  ubicacion: z.string().optional(),
}).refine((d) => {
  if (d.fechaExacta) return true;
  // si no hay fechaExacta, entonces ambos extremos o ninguno
  return (!d.fechaInicio && !d.fechaFin) || (Boolean(d.fechaInicio) && Boolean(d.fechaFin));
}, { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." });

export class CronogramaService {
  constructor(private prisma: PrismaClient, private conjuntoId: string) {}

  async tareasPorOperario(payload: unknown) {
    const { operarioId } = OperarioIdDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: { conjuntoId: this.conjuntoId, operarioId },
    });
  }

  async tareasPorFecha(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
    });
  }

  async tareasEnRango(payload: unknown) {
    const { fechaInicio, fechaFin } = RangoFechasDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaFin: { gte: fechaInicio },
        fechaInicio: { lte: fechaFin },
      },
    });
  }

  async tareasPorUbicacion(payload: unknown) {
    const { ubicacion } = z.object({ ubicacion: z.string().min(1) }).parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        ubicacion: { nombre: { equals: ubicacion, mode: "insensitive" } },
      },
    });
  }

  async tareasPorFiltro(payload: unknown) {
    const f = TareasPorFiltroDTO.parse(payload);

    const fechaInicio =
      f.fechaExacta ?? f.fechaInicio ?? undefined;
    const fechaFin =
      f.fechaExacta ?? f.fechaFin ?? undefined;

    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarioId: f.operarioId,
        fechaInicio: fechaInicio ? { lte: fechaFin! } : undefined,
        fechaFin: fechaFin ? { gte: fechaInicio! } : undefined,
        ubicacion: f.ubicacion
          ? { nombre: { equals: f.ubicacion, mode: "insensitive" } }
          : undefined,
      },
    });
  }

  /**
   * Útil para FullCalendar u otros calendarios.
   * Devuelve eventos con título y metadatos de recurso.
   */
  async exportarComoEventosCalendario() {
    const tareas = await this.prisma.tarea.findMany({
      where: { conjuntoId: this.conjuntoId },
      include: {
        ubicacion: true,
        elemento: true,
        operario: { include: { usuario: true } },
      },
    });

    return tareas.map((t) => ({
      title: `${t.descripcion} - ${t.operario?.usuario?.nombre ?? "Sin asignar"}`,
      start: t.fechaInicio.toISOString(),
      end: t.fechaFin.toISOString(),
      resource: {
        operario: t.operario?.usuario?.nombre ?? null,
        ubicacion: t.ubicacion?.nombre ?? null,
        elemento: t.elemento?.nombre ?? null,
      },
    }));
  }
}
