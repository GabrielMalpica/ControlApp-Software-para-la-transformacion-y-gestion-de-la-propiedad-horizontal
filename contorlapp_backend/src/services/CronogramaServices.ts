// src/services/CronogramaService.ts
import { PrismaClient } from "../generated/prisma";
import { z } from "zod";

// DTOs locales de filtros para este servicio
const OperarioIdDTO = z.object({ operarioId: z.number().int().positive() });
const FechaDTO = z.object({ fecha: z.coerce.date() });
const RangoFechasDTO = z
  .object({
    fechaInicio: z.coerce.date(),
    fechaFin: z.coerce.date(),
  })
  .refine((d) => d.fechaFin >= d.fechaInicio, {
    message: "fechaFin debe ser mayor o igual a fechaInicio",
    path: ["fechaFin"],
  });

const TareasPorFiltroDTO = z
  .object({
    operarioId: z.number().int().positive().optional(),
    fechaExacta: z.coerce.date().optional(),
    fechaInicio: z.coerce.date().optional(),
    fechaFin: z.coerce.date().optional(),
    ubicacion: z.string().optional(),
  })
  .refine(
    (d) => {
      if (d.fechaExacta) return true;
      return (
        (!d.fechaInicio && !d.fechaFin) ||
        (Boolean(d.fechaInicio) && Boolean(d.fechaFin))
      );
    },
    { message: "Debe enviar fechaExacta o un rango (fechaInicio y fechaFin)." }
  );

/** Util: sumar minutos a una fecha (sin mutar la original) */
function addMinutes(d: Date, minutes: number) {
  return new Date(d.getTime() + minutes * 60 * 1000);
}

/** Util: devuelve el lunes de la semana de una fecha (semana ISO) */
function mondayOfWeek(d: Date) {
  const day = d.getDay(); // 0 dom - 6 sab
  const diff = d.getDate() - day + (day === 0 ? -6 : 1);
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}

/** Util: simple chequeo de solapamiento de intervalos [a,b] con [c,d] (inclusive) */
function overlap(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) {
  return aStart <= bEnd && bStart <= aEnd;
}

export class CronogramaService {
  constructor(private prisma: PrismaClient, private conjuntoId: string) {}

  /* ==================== Consultas básicas ==================== */

  async tareasPorOperario(payload: unknown) {
    const { operarioId } = OperarioIdDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarios: { some: { id: operarioId } },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
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
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async tareasEnRango(payload: unknown) {
    const { fechaInicio, fechaFin } = RangoFechasDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        // solape de rangos
        fechaFin: { gte: fechaInicio },
        fechaInicio: { lte: fechaFin },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async tareasPorUbicacion(payload: unknown) {
    const { ubicacion } = z
      .object({ ubicacion: z.string().min(1) })
      .parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        // según tu versión de Prisma, podrías necesitar { is: { nombre: ... } }
        ubicacion: { nombre: { equals: ubicacion, mode: "insensitive" } },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async tareasPorFiltro(payload: unknown) {
    const f = TareasPorFiltroDTO.parse(payload);

    // Si llega fechaExacta, interpretamos el día completo
    let fechaInicio: Date | undefined;
    let fechaFin: Date | undefined;

    if (f.fechaExacta) {
      const d0 = new Date(f.fechaExacta);
      fechaInicio = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate(), 0, 0, 0, 0);
      fechaFin = new Date(d0.getFullYear(), d0.getMonth(), d0.getDate(), 23, 59, 59, 999);
    } else {
      fechaInicio = f.fechaInicio ?? undefined;
      fechaFin = f.fechaFin ?? undefined;
    }

    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarios: f.operarioId ? { some: { id: f.operarioId } } : undefined,
        fechaInicio: fechaFin ? { lte: fechaFin } : undefined,
        fechaFin: fechaInicio ? { gte: fechaInicio } : undefined,
        ubicacion: f.ubicacion
          ? { nombre: { equals: f.ubicacion, mode: "insensitive" } }
          : undefined,
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  /* ==================== Calendario / UI por bloques ==================== */

  /**
   * Vista diaria agrupada por franjas (por defecto 60 min).
   * Devuelve array de:
   *  { inicio: Date, fin: Date, tareas: [{ id, descripcion, operarios: [{id, nombre}], ubicacion, elemento, ... }] }
   */
  async vistaDiariaPorHoras(payload: unknown, pasoMinutos = 60) {
    const { fecha } = FechaDTO.parse(payload);

    const inicioDia = new Date(fecha);
    inicioDia.setHours(0, 0, 0, 0);
    const finDia = new Date(fecha);
    finDia.setHours(23, 59, 59, 999);

    // Trae todas las tareas que toquen el día
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaFin: { gte: inicioDia },
        fechaInicio: { lte: finDia },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: { fechaInicio: "asc" },
    });

    // Creamos las franjas
    const slots: Array<{ inicio: Date; fin: Date; tareas: any[] }> = [];
    let cursor = new Date(inicioDia);
    while (cursor <= finDia) {
      const slotInicio = new Date(cursor);
      const slotFin = addMinutes(slotInicio, pasoMinutos);
      slots.push({ inicio: slotInicio, fin: slotFin, tareas: [] });
      cursor = slotFin;
    }

    // Asignamos tareas a franjas si se solapan
    for (const t of tareas) {
      for (const s of slots) {
        if (overlap(t.fechaInicio, t.fechaFin, s.inicio, s.fin)) {
          s.tareas.push({
            id: t.id,
            descripcion: t.descripcion,
            operarios: t.operarios.map((o) => ({
              id: o.id,
              nombre: o.usuario?.nombre ?? null,
            })),
            ubicacion: t.ubicacion?.nombre ?? null,
            elemento: t.elemento?.nombre ?? null,
            desde: t.fechaInicio,
            hasta: t.fechaFin,
          });
        }
      }
    }

    return slots;
  }

  /**
   * Vista semanal por franjas (lunes a domingo).
   * `inicioSemanaISO`: fecha dentro de la semana deseada (cualquier día). Se normaliza a lunes.
   */
  async vistaSemanalPorHoras(inicioSemanaISO: Date, pasoMinutos = 60) {
    const lunes = mondayOfWeek(inicioSemanaISO);
    const domingo = new Date(lunes);
    domingo.setDate(lunes.getDate() + 6);
    domingo.setHours(23, 59, 59, 999);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        fechaFin: { gte: lunes },
        fechaInicio: { lte: domingo },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: true,
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    // Creamos días -> franjas
    const dias: Record<
      string,
      Array<{ inicio: Date; fin: Date; tareas: any[] }>
    > = {};
    for (let d = 0; d < 7; d++) {
      const dia = new Date(lunes);
      dia.setDate(lunes.getDate() + d);
      dia.setHours(0, 0, 0, 0);
      const finDia = new Date(dia);
      finDia.setHours(23, 59, 59, 999);

      const slots: Array<{ inicio: Date; fin: Date; tareas: any[] }> = [];
      let cursor = new Date(dia);
      while (cursor <= finDia) {
        const slotInicio = new Date(cursor);
        const slotFin = addMinutes(slotInicio, pasoMinutos);
        slots.push({ inicio: slotInicio, fin: slotFin, tareas: [] });
        cursor = slotFin;
      }
      dias[dia.toISOString().slice(0, 10)] = slots; // clave por YYYY-MM-DD
    }

    // Poblamos por solapamiento
    for (const t of tareas) {
      for (const key of Object.keys(dias)) {
        const slots = dias[key];
        for (const s of slots) {
          if (overlap(t.fechaInicio, t.fechaFin, s.inicio, s.fin)) {
            s.tareas.push({
              id: t.id,
              descripcion: t.descripcion,
              operarios: t.operarios.map((o) => ({
                id: o.id,
                nombre: o.usuario?.nombre ?? null,
              })),
              ubicacion: t.ubicacion?.nombre ?? null,
              elemento: t.elemento?.nombre ?? null,
              desde: t.fechaInicio,
              hasta: t.fechaFin,
            });
          }
        }
      }
    }

    return dias;
  }

  /* ==================== Choques y utilidades ==================== */

  /** Devuelve las tareas del operario que se pisan entre sí dentro del rango dado (M:N) */
  async detectarChoques(payload: unknown) {
    const { operarioId, fechaInicio, fechaFin } = z
      .object({
        operarioId: z.number().int().positive(),
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      })
      .parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        operarios: { some: { id: operarioId } },
        fechaFin: { gte: fechaInicio },
        fechaInicio: { lte: fechaFin },
      },
      orderBy: [{ fechaInicio: "asc" }],
    });

    const choques: Array<{ aId: number; bId: number }> = [];
    for (let i = 0; i < tareas.length; i++) {
      for (let j = i + 1; j < tareas.length; j++) {
        if (
          overlap(
            tareas[i].fechaInicio,
            tareas[i].fechaFin,
            tareas[j].fechaInicio,
            tareas[j].fechaFin
          )
        ) {
          choques.push({ aId: tareas[i].id, bId: tareas[j].id });
        }
      }
    }
    return choques;
  }

  /** Reprograma fechas de una tarea (sin tocar operarios/ubicación/elemento) */
  async reprogramarTarea(payload: unknown) {
    const { tareaId, fechaInicio, fechaFin } = z
      .object({
        tareaId: z.number().int().positive(),
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      })
      .refine((d) => d.fechaFin >= d.fechaInicio, {
        message: "fechaFin debe ser >= fechaInicio",
      })
      .parse(payload);

    return this.prisma.tarea.update({
      where: { id: tareaId },
      data: { fechaInicio, fechaFin },
    });
  }

  /* ==================== Export para calendarios ==================== */

  /**
   * Útil para FullCalendar u otros calendarios.
   * Devuelve eventos con título y metadatos de recursos.
   */
  async exportarComoEventosCalendario() {
    const tareas = await this.prisma.tarea.findMany({
      where: { conjuntoId: this.conjuntoId },
      include: {
        ubicacion: true,
        elemento: true,
        operarios: { include: { usuario: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    return tareas.map((t) => {
      const nombresOperarios = t.operarios
        .map((o) => o.usuario?.nombre)
        .filter(Boolean)
        .join(", ") || "Sin asignar";

      return {
        title: `${t.descripcion} - ${nombresOperarios}`,
        start: t.fechaInicio.toISOString(),
        end: t.fechaFin.toISOString(),
        resource: {
          operarios: t.operarios.map((o) => ({
            id: o.id,
            nombre: o.usuario?.nombre ?? null,
          })),
          ubicacion: t.ubicacion?.nombre ?? null,
          elemento: t.elemento?.nombre ?? null,
        },
      };
    });
  }
}
