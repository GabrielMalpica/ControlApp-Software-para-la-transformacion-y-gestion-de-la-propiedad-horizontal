// src/services/ReporteService.ts
import { PrismaClient, EstadoTarea } from "../generated/prisma";
import { z } from "zod";
import { decToNumber } from "../utils/decimal";

/** ======================
 * DTOs
 * ====================== */

const RangoBaseDTO = z.object({
  desde: z.coerce.date(),
  hasta: z.coerce.date(),
});

const RangoDTO = RangoBaseDTO.refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const RangoConConjuntoDTO = RangoBaseDTO.merge(
  z.object({ conjuntoId: z.string().min(1) }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const RangoConConjuntoOpcionalDTO = RangoBaseDTO.merge(
  z.object({ conjuntoId: z.string().min(1).optional() }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const TareasPorEstadoDTO = RangoBaseDTO.merge(
  z.object({
    conjuntoId: z.string().min(1),
    estado: z.nativeEnum(EstadoTarea),
  }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const RangoConOperarioOpcionalDTO = RangoBaseDTO.merge(
  z.object({
    operarioId: z.string().min(1).optional(), // ✅ Operario.id es string
    conjuntoId: z.string().min(1).optional(),
  }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

const ZonificacionPreventivasDTO = RangoBaseDTO.merge(
  z.object({
    conjuntoId: z.string().min(1).optional(),
    soloActivas: z.boolean().optional(),
  }),
).refine((d) => d.hasta >= d.desde, {
  path: ["hasta"],
  message: "hasta debe ser >= desde",
});

/** ======================
 * Tipos de salida
 * ====================== */

type RowOperario = {
  operarioId: string;
  nombre: string;
  total: number;
  aprobadas: number;
  rechazadas: number;
  noCompletadas: number;
  pendientesAprobacion: number;
  minutosPromedio: number;
};

function dayKey(d: Date) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}
function addDays(date: Date, n: number) {
  const d = new Date(date);
  d.setDate(d.getDate() + n);
  return d;
}
function buildDayRange(desde: Date, hasta: Date) {
  const out: string[] = [];
  let cur = new Date(desde.getFullYear(), desde.getMonth(), desde.getDate());
  const end = new Date(hasta.getFullYear(), hasta.getMonth(), hasta.getDate());
  while (cur <= end) {
    out.push(dayKey(cur));
    cur = addDays(cur, 1);
  }
  return out;
}

type PlanInsumoItem = {
  insumoId: number;
  consumoPorUnidad: number;
};

type InsumoAgg = {
  insumoId: number;
  nombre: string;
  unidad: string;
  consumoEstimado: number;
  usos: number;
  consumoPorUnidadAcumulado: number;
  consumoPorUnidadMuestras: number;
  rendimientoAcumulado: number;
  rendimientoMuestras: number;
};

type UbicacionAgg = {
  ubicacionId: number;
  ubicacionNombre: string;
  unidadCalculo: string | null;
  preventivas: number;
  areaTotal: number;
  insumos: Map<string, InsumoAgg>;
};

type ConjuntoAgg = {
  conjuntoId: string;
  conjuntoNombre: string;
  preventivas: number;
  areaTotal: number;
  ubicaciones: Map<number, UbicacionAgg>;
  insumos: Map<string, InsumoAgg>;
};

function toNumberSafe(v: unknown): number {
  if (v == null) return 0;
  if (typeof v === "number") return Number.isFinite(v) ? v : 0;
  const parsed = Number(String(v).replace(",", "."));
  return Number.isFinite(parsed) ? parsed : 0;
}

function toStringSafe(v: unknown, fallback = ""): string {
  const s = String(v ?? "").trim();
  return s.length > 0 ? s : fallback;
}

function parsePlanInsumos(raw: unknown): PlanInsumoItem[] {
  let source: unknown = raw;
  if (typeof source === "string") {
    try {
      source = JSON.parse(source);
    } catch {
      source = [];
    }
  }
  if (!Array.isArray(source)) return [];

  const out: PlanInsumoItem[] = [];
  for (const item of source) {
    if (!item || typeof item !== "object") continue;
    const obj = item as Record<string, unknown>;
    const insumoId = Math.trunc(
      toNumberSafe(obj.insumoId ?? obj.id ?? obj.insumo_id),
    );
    const consumoPorUnidad = toNumberSafe(
      obj.consumoPorUnidad ??
        obj.consumo ??
        obj.cantidadPorUnidad ??
        obj.cantidad,
    );
    if (insumoId > 0 && consumoPorUnidad > 0) {
      out.push({ insumoId, consumoPorUnidad });
    }
  }
  return out;
}

function calcConsumoEstimado(
  areaNumerica: number,
  consumoPorUnidad: number,
): number {
  if (consumoPorUnidad <= 0) return 0;
  if (areaNumerica > 0) return areaNumerica * consumoPorUnidad;
  return consumoPorUnidad;
}

function calcRendimientoInsumo(
  areaNumerica: number,
  consumoEstimado: number,
): number | null {
  if (areaNumerica <= 0 || consumoEstimado <= 0) return null;
  return areaNumerica / consumoEstimado;
}

function makeInsumoKey(insumoId: number, nombre: string, unidad: string): string {
  return insumoId > 0
    ? `id:${insumoId}`
    : `${nombre.toUpperCase()}|${unidad.toUpperCase()}`;
}

function pushInsumoAgg(
  bucket: Map<string, InsumoAgg>,
  params: {
    key: string;
    insumoId: number;
    nombre: string;
    unidad: string;
    consumoEstimado: number;
    consumoPorUnidad: number;
    rendimiento: number | null;
  },
) {
  const current = bucket.get(params.key) ?? {
    insumoId: params.insumoId,
    nombre: params.nombre,
    unidad: params.unidad,
    consumoEstimado: 0,
    usos: 0,
    consumoPorUnidadAcumulado: 0,
    consumoPorUnidadMuestras: 0,
    rendimientoAcumulado: 0,
    rendimientoMuestras: 0,
  };

  current.consumoEstimado += params.consumoEstimado;
  current.usos += 1;

  if (params.consumoPorUnidad > 0) {
    current.consumoPorUnidadAcumulado += params.consumoPorUnidad;
    current.consumoPorUnidadMuestras += 1;
  }
  if (params.rendimiento != null && params.rendimiento > 0) {
    current.rendimientoAcumulado += params.rendimiento;
    current.rendimientoMuestras += 1;
  }

  bucket.set(params.key, current);
}

function toOutInsumoRow(i: InsumoAgg) {
  const consumoPorUnidadPromedio =
    i.consumoPorUnidadMuestras > 0
      ? i.consumoPorUnidadAcumulado / i.consumoPorUnidadMuestras
      : 0;
  const rendimientoPromedio =
    i.rendimientoMuestras > 0
      ? i.rendimientoAcumulado / i.rendimientoMuestras
      : null;

  return {
    insumoId: i.insumoId,
    nombre: i.nombre,
    unidad: i.unidad,
    consumoEstimado: Number(i.consumoEstimado.toFixed(4)),
    usos: i.usos,
    consumoPorUnidadPromedio: Number(consumoPorUnidadPromedio.toFixed(6)),
    rendimientoPromedio:
      rendimientoPromedio == null
        ? null
        : Number(rendimientoPromedio.toFixed(6)),
    formulaConsumoEstimado: "areaNumerica * consumoPorUnidad",
    formulaRendimiento: "areaNumerica / consumoEstimado",
  };
}

export class ReporteService {
  constructor(private prisma: PrismaClient) {}

  // =========================================================
  // ✅ MÉTODOS QUE YA TENÍAS (NO SE BORRAN)
  // =========================================================

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

      return {
        id: t.id,
        descripcion: t.descripcion,
        ubicacion: t.ubicacion?.nombre ?? "Sin ubicación",
        elemento: t.elemento?.nombre ?? "Sin elemento",
        responsable:
          nombresOperarios.length > 0
            ? nombresOperarios.join(", ")
            : "Sin asignar",
        estado: t.estado,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
      };
    });
  }

  // =========================================================
  // 1) KPI general del rango (opcional por conjunto)
  // =========================================================
  async kpis(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const where = {
      ...(conjuntoId ? { conjuntoId } : {}),
      fechaInicio: { gte: desde },
      fechaFin: { lte: hasta },
    };

    const grouped = await this.prisma.tarea.groupBy({
      by: ["estado"],
      where,
      _count: { _all: true },
    });

    const total = grouped.reduce((acc, r) => acc + (r._count?._all ?? 0), 0);
    const byEstado: Record<string, number> = {};
    for (const r of grouped) byEstado[r.estado] = r._count?._all ?? 0;

    const aprobadas = byEstado[EstadoTarea.APROBADA] ?? 0;
    const pendientesAprobacion =
      byEstado[EstadoTarea.PENDIENTE_APROBACION] ?? 0;
    const rechazadas = byEstado[EstadoTarea.RECHAZADA] ?? 0;
    const noCompletadas = byEstado[EstadoTarea.NO_COMPLETADA] ?? 0;
    const asignadas = byEstado[EstadoTarea.ASIGNADA] ?? 0;
    const enProceso = byEstado[EstadoTarea.EN_PROCESO] ?? 0;
    const completadas = byEstado[EstadoTarea.COMPLETADA] ?? 0;

    // sugerido: "cerradas operativamente"
    const cerradasOperativas =
      aprobadas + rechazadas + noCompletadas + completadas;
    const tasaCierre =
      total > 0 ? Math.round((cerradasOperativas / total) * 100) : 0;

    return {
      ok: true,
      total,
      byEstado,
      kpi: {
        asignadas,
        enProceso,
        completadas,
        aprobadas,
        pendientesAprobacion,
        rechazadas,
        noCompletadas,
        cerradasOperativas,
        tasaCierrePct: tasaCierre,
      },
    };
  }

  // =========================================================
  // 2) Serie diaria por estado (para gráfica de línea)
  // =========================================================
  async serieDiariaPorEstado(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        ...(conjuntoId ? { conjuntoId } : {}),
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      select: { estado: true, fechaFin: true },
    });

    const days = buildDayRange(desde, hasta);
    const series: Record<string, Record<string, number>> = {};
    for (const d of days) series[d] = {};

    for (const t of tareas) {
      const dk = dayKey(t.fechaFin);
      if (!series[dk]) continue;
      series[dk][t.estado] = (series[dk][t.estado] ?? 0) + 1;
    }

    return { ok: true, days, series };
  }

  // =========================================================
  // 3) Resumen por conjunto (barras)
  // =========================================================
  async resumenPorConjunto(payload: unknown) {
    const { desde, hasta } = RangoDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      select: {
        estado: true,
        conjuntoId: true,
        conjunto: { select: { nombre: true, nit: true } },
      },
    });

    const map = new Map<
      string,
      {
        conjuntoId: string;
        conjuntoNombre: string;
        nit: string;
        total: number;
        aprobadas: number;
        rechazadas: number;
        noCompletadas: number;
        pendientesAprobacion: number;
      }
    >();

    for (const t of tareas) {
      const key = t.conjuntoId ?? "SIN_CONJUNTO";
      if (!map.has(key)) {
        map.set(key, {
          conjuntoId: key,
          conjuntoNombre: t.conjunto?.nombre ?? "Sin nombre",
          nit: t.conjunto?.nit ?? key,
          total: 0,
          aprobadas: 0,
          rechazadas: 0,
          noCompletadas: 0,
          pendientesAprobacion: 0,
        });
      }
      const row = map.get(key)!;
      row.total++;

      if (t.estado === EstadoTarea.APROBADA) row.aprobadas++;
      if (t.estado === EstadoTarea.RECHAZADA) row.rechazadas++;
      if (t.estado === EstadoTarea.NO_COMPLETADA) row.noCompletadas++;
      if (t.estado === EstadoTarea.PENDIENTE_APROBACION)
        row.pendientesAprobacion++;
    }

    const data = Array.from(map.values()).sort((a, b) => b.total - a.total);
    return { ok: true, data };
  }

  // =========================================================
  // 4) Resumen por operario (barras + ranking)
  // =========================================================
  async resumenPorOperario(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        ...(conjuntoId ? { conjuntoId } : {}),
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      select: {
        estado: true,
        fechaInicio: true,
        fechaFin: true,
        operarios: {
          select: { id: true, usuario: { select: { nombre: true } } },
        },
      },
    });

    const map = new Map<string, RowOperario>();

    for (const t of tareas) {
      const durMin = Math.max(
        0,
        Math.round((t.fechaFin.getTime() - t.fechaInicio.getTime()) / 60000),
      );

      for (const op of t.operarios ?? []) {
        const id = op.id; // ✅ string

        if (!map.has(id)) {
          map.set(id, {
            operarioId: id,
            nombre: op.usuario?.nombre ?? `Operario ${id}`,
            total: 0,
            aprobadas: 0,
            rechazadas: 0,
            noCompletadas: 0,
            pendientesAprobacion: 0,
            minutosPromedio: 0,
          });
        }

        const row = map.get(id)!;
        row.total++;

        if (t.estado === EstadoTarea.APROBADA) row.aprobadas++;
        if (t.estado === EstadoTarea.RECHAZADA) row.rechazadas++;
        if (t.estado === EstadoTarea.NO_COMPLETADA) row.noCompletadas++;
        if (t.estado === EstadoTarea.PENDIENTE_APROBACION)
          row.pendientesAprobacion++;

        row.minutosPromedio = Math.round(
          (row.minutosPromedio * (row.total - 1) + durMin) / row.total,
        );
      }
    }

    const data = Array.from(map.values()).sort((a, b) => b.total - a.total);
    return { ok: true, data };
  }

  // =========================================================
  // 5) Insumos por rango (por conjunto obligatorio)
  // =========================================================
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
        tipo: "SALIDA" as any, // si tu enum es TipoMovimientoInsumo.SALIDA, ajústalo si aplica
      },
      _sum: { cantidad: true },
      _count: { _all: true },
    });

    const insumos = await this.prisma.insumo.findMany({
      where: { id: { in: rows.map((r) => r.insumoId) } },
      select: { id: true, nombre: true, unidad: true },
    });

    const mapInfo = new Map(insumos.map((i) => [i.id, i]));

    const data = rows
      .map((r) => {
        const info = mapInfo.get(r.insumoId);
        return {
          insumoId: r.insumoId,
          nombre: info?.nombre ?? `Insumo ${r.insumoId}`,
          unidad: info?.unidad ?? "",
          cantidad: decToNumber(r._sum.cantidad),
          usos: r._count?._all ?? 0,
        };
      })
      .sort((a, b) => b.cantidad - a.cantidad);

    return { ok: true, data };
  }

  // =========================================================
  // 6) Maquinaria más usada (por conjunto opcional)
  // =========================================================
  async usoMaquinariaTop(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const rows = await this.prisma.usoMaquinaria.groupBy({
      by: ["maquinariaId"],
      where: {
        fechaInicio: { gte: desde, lte: hasta },
        ...(conjuntoId ? { tarea: { conjuntoId } } : {}), // ✅ así sí
      },
      _count: { _all: true },
    });

    const maquinariaIds = rows.map((r) => r.maquinariaId);

    const maqs = maquinariaIds.length
      ? await this.prisma.maquinaria.findMany({
          where: { id: { in: maquinariaIds } },
          select: { id: true, nombre: true },
        })
      : [];

    const mapInfo = new Map<number, { id: number; nombre: string | null }>(
      maqs.map((m) => [m.id, m]),
    );

    const data = rows
      .map((r) => {
        const info = mapInfo.get(r.maquinariaId);
        return {
          maquinariaId: r.maquinariaId,
          nombre: info?.nombre ?? `Maquinaria ${r.maquinariaId}`,
          usos: r._count._all,
        };
      })
      .sort((a, b) => b.usos - a.usos);

    return { ok: true, data };
  }

  // =========================================================
  // 7) Herramientas más usadas (por conjunto opcional)
  // =========================================================
  async usoHerramientaTop(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const rows = await this.prisma.usoHerramienta.groupBy({
      by: ["herramientaId"],
      where: {
        fechaInicio: { gte: desde, lte: hasta },
        ...(conjuntoId ? { tarea: { conjuntoId } } : {}),
      },
      _count: { _all: true },
      _sum: { cantidad: true },
    });

    const herramientaIds = rows.map((r) => r.herramientaId);

    const herrs = herramientaIds.length
      ? await this.prisma.herramienta.findMany({
          where: { id: { in: herramientaIds } },
          select: { id: true, nombre: true, unidad: true },
        })
      : [];

    const mapInfo = new Map<
      number,
      { id: number; nombre: string; unidad: string }
    >(herrs.map((h) => [h.id, h]));

    const data = rows
      .map((r) => {
        const info = mapInfo.get(r.herramientaId);
        return {
          herramientaId: r.herramientaId,
          nombre: info?.nombre ?? `Herramienta ${r.herramientaId}`,
          unidad: info?.unidad ?? null,
          usos: r._count._all,
          cantidad: decToNumber(r._sum.cantidad), // Decimal -> number
        };
      })
      .sort((a, b) => b.usos - a.usos);

    return { ok: true, data };
  }

  // =========================================================
  // 8) Duración promedio por estado (conjunto opcional)
  // =========================================================
  async duracionPromedioPorEstado(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        ...(conjuntoId ? { conjuntoId } : {}),
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      select: { estado: true, duracionMinutos: true },
    });

    const acc: Record<string, { sum: number; count: number }> = {};
    for (const t of tareas) {
      const min = t.duracionMinutos ?? 0;
      if (!acc[t.estado]) acc[t.estado] = { sum: 0, count: 0 };
      acc[t.estado].sum += min;
      acc[t.estado].count += 1;
    }

    const data = Object.entries(acc).map(([estado, v]) => ({
      estado,
      minutosPromedio: v.count > 0 ? Math.round(v.sum / v.count) : 0,
      cantidad: v.count,
    }));

    data.sort((a, b) => b.cantidad - a.cantidad);
    return { ok: true, data };
  }

  // =========================================================
  // 9) Dataset mensual para PDF (ya con insumos/maquinaria/herramientas reales)
  // =========================================================
  async reporteMensualDetalle(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        ...(conjuntoId ? { conjuntoId } : {}),
        fechaInicio: { gte: desde },
        fechaFin: { lte: hasta },
      },
      orderBy: [{ fechaFin: "asc" }, { id: "asc" }],
      include: {
        conjunto: true,
        ubicacion: true,
        elemento: true,
        supervisor: { include: { usuario: true } },
        operarios: { include: { usuario: true } },
      },
    });

    const ids = tareas.map((t) => t.id);

    // Insumos por tarea (ConsumoInsumo sí tiene fecha)
    const consumos = await this.prisma.consumoInsumo.findMany({
      where: {
        tareaId: { in: ids },
        fecha: { gte: desde, lte: hasta },
      },
      include: { insumo: true, operario: { include: { usuario: true } } },
      orderBy: [{ fecha: "asc" }, { id: "asc" }],
    });

    const insumosPorTarea = new Map<number, any[]>();
    for (const c of consumos) {
      const tid = c.tareaId;
      if (!tid) continue;
      if (!insumosPorTarea.has(tid)) insumosPorTarea.set(tid, []);
      insumosPorTarea.get(tid)!.push({
        id: c.id,
        fecha: c.fecha,
        insumoId: c.insumoId,
        nombre: c.insumo?.nombre ?? null,
        unidad: c.insumo?.unidad ?? null,
        cantidad: decToNumber(c.cantidad),
        tipo: c.tipo,
        operario: c.operario?.usuario?.nombre ?? null,
        observacion: c.observacion ?? null,
      });
    }

    // Maquinaria por tarea (UsoMaquinaria NO tiene fecha, tiene fechaInicio/fechaFin)
    const usoMaq = await this.prisma.usoMaquinaria.findMany({
      where: {
        tareaId: { in: ids },
        fechaInicio: { gte: desde, lte: hasta },
        ...(conjuntoId ? { tarea: { conjuntoId } } : {}),
      },
      include: {
        maquinaria: true,
        operario: { include: { usuario: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    const maquinariaPorTarea = new Map<number, any[]>();
    for (const r of usoMaq as any[]) {
      const tid = r.tareaId;
      if (!tid) continue;
      if (!maquinariaPorTarea.has(tid)) maquinariaPorTarea.set(tid, []);
      maquinariaPorTarea.get(tid)!.push({
        id: r.id,
        fechaInicio: r.fechaInicio,
        fechaFin: r.fechaFin ?? null,
        maquinariaId: r.maquinariaId,
        nombre: r.maquinaria?.nombre ?? null,
        marca: r.maquinaria?.marca ?? null,
        tipo: r.maquinaria?.tipo ?? null,
        operario: r.operario?.usuario?.nombre ?? null,
        observacion: r.observacion ?? null,
      });
    }

    // Herramientas por tarea (debe ser igual: fechaInicio/fechaFin)
    const usoHerr = await this.prisma.usoHerramienta.findMany({
      where: {
        tareaId: { in: ids },
        fechaInicio: { gte: desde, lte: hasta },
        ...(conjuntoId ? { tarea: { conjuntoId } } : {}),
      },
      include: {
        herramienta: true,
        operario: { include: { usuario: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    const herramientasPorTarea = new Map<number, any[]>();
    for (const r of usoHerr as any[]) {
      const tid = r.tareaId;
      if (!tid) continue;
      if (!herramientasPorTarea.has(tid)) herramientasPorTarea.set(tid, []);
      herramientasPorTarea.get(tid)!.push({
        id: r.id,
        fechaInicio: r.fechaInicio,
        fechaFin: r.fechaFin ?? null,
        herramientaId: r.herramientaId,
        nombre: r.herramienta?.nombre ?? null,
        unidad: r.herramienta?.unidad ?? null,
        cantidad: decToNumber(r.cantidad),
        operario: r.operario?.usuario?.nombre ?? null,
        observacion: r.observacion ?? null,
      });
    }

    // Construcción final
    const data = tareas.map((t) => {
      const operarios = (t.operarios ?? [])
        .map((op) => op.usuario?.nombre)
        .filter((x): x is string => Boolean(x));

      return {
        id: t.id,
        tipo: t.tipo,
        descripcion: t.descripcion,
        estado: t.estado,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        duracionMinutos: t.duracionMinutos,
        fechaVerificacion: t.fechaVerificacion ?? null,

        conjunto: {
          id: t.conjuntoId,
          nombre: t.conjunto?.nombre ?? null,
          nit: t.conjunto?.nit ?? null,
        },
        ubicacion: { nombre: t.ubicacion?.nombre ?? null },
        elemento: { nombre: t.elemento?.nombre ?? null },

        supervisor: t.supervisor?.usuario?.nombre ?? null,
        operarios,

        observaciones: t.observaciones ?? null,
        observacionesRechazo: t.observacionesRechazo ?? null,

        evidencias: t.evidencias ?? [],

        insumos: insumosPorTarea.get(t.id) ?? [],
        maquinaria: maquinariaPorTarea.get(t.id) ?? [],
        herramientas: herramientasPorTarea.get(t.id) ?? [],

        insumosUsados: t.insumosUsados ?? null,
        insumosPlanJson: (t as any).insumosPlanJson ?? null,
        maquinariaPlanJson: (t as any).maquinariaPlanJson ?? null,
        herramientasPlanJson: (t as any).herramientasPlanJson ?? null,
      };
    });

    return { ok: true, data };
  }

  // 10) Conteo por tipo (PREVENTIVA vs CORRECTIVA)
  async conteoPorTipo(payload: unknown) {
    const { desde, hasta, conjuntoId } =
      RangoConConjuntoOpcionalDTO.parse(payload);

    const where = {
      ...(conjuntoId ? { conjuntoId } : {}),
      fechaInicio: { gte: desde },
      fechaFin: { lte: hasta },
    };

    const grouped = await this.prisma.tarea.groupBy({
      by: ["tipo"],
      where,
      _count: { _all: true },
    });

    const out: Record<string, number> = {};
    for (const r of grouped) out[r.tipo] = r._count._all;

    return {
      ok: true,
      data: {
        preventivas: out["PREVENTIVA"] ?? 0,
        correctivas: out["CORRECTIVA"] ?? 0,
        otros: Object.entries(out)
          .filter(([k]) => k !== "PREVENTIVA" && k !== "CORRECTIVA")
          .reduce((a, [, v]) => a + v, 0),
      },
    };
  }

  // 11) ZonificaciÃ³n de preventivas por conjunto/ubicaciÃ³n (Ã¡rea + rendimiento estimado)
  async zonificacionPreventivas(payload: unknown) {
    const {
      desde,
      hasta,
      conjuntoId,
      soloActivas: soloActivasRaw,
    } = ZonificacionPreventivasDTO.parse(payload);
    const soloActivas = soloActivasRaw ?? true;

    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: {
        ...(conjuntoId ? { conjuntoId } : {}),
        ...(soloActivas ? { activo: true } : {}),
        creadoEn: { gte: desde, lte: hasta },
      },
      select: {
        id: true,
        conjuntoId: true,
        areaNumerica: true,
        unidadCalculo: true,
        ubicacionId: true,
        insumoPrincipalId: true,
        consumoPrincipalPorUnidad: true,
        insumosPlanJson: true,
        conjunto: { select: { nit: true, nombre: true } },
        ubicacion: { select: { id: true, nombre: true } },
      },
      orderBy: [{ conjuntoId: "asc" }, { ubicacionId: "asc" }, { id: "asc" }],
    });

    const insumoIds = new Set<number>();
    for (const d of defs) {
      if (d.insumoPrincipalId != null && d.insumoPrincipalId > 0) {
        insumoIds.add(d.insumoPrincipalId);
      }
      for (const p of parsePlanInsumos(d.insumosPlanJson)) {
        if (p.insumoId > 0) insumoIds.add(p.insumoId);
      }
    }

    const insumoRows =
      insumoIds.size > 0
        ? await this.prisma.insumo.findMany({
            where: { id: { in: Array.from(insumoIds) } },
            select: { id: true, nombre: true, unidad: true },
          })
        : [];
    const insumoInfo = new Map(
      insumoRows.map((i) => [i.id, { nombre: i.nombre, unidad: i.unidad }]),
    );

    const conjuntos = new Map<string, ConjuntoAgg>();
    const topGlobal = new Map<string, InsumoAgg>();

    let totalPreventivas = 0;
    let totalArea = 0;

    for (const d of defs) {
      const cId = d.conjuntoId;
      const cNombre = d.conjunto?.nombre?.trim() || cId;
      const uId = d.ubicacionId;
      const uNombre = d.ubicacion?.nombre?.trim() || `Ubicacion ${uId}`;
      const unidadCalculo = d.unidadCalculo?.toString() ?? null;
      const area = Math.max(0, toNumberSafe(d.areaNumerica));

      const conjAgg = conjuntos.get(cId) ?? {
        conjuntoId: cId,
        conjuntoNombre: cNombre,
        preventivas: 0,
        areaTotal: 0,
        ubicaciones: new Map<number, UbicacionAgg>(),
        insumos: new Map<string, InsumoAgg>(),
      };
      conjAgg.preventivas += 1;
      conjAgg.areaTotal += area;

      const ubicAgg = conjAgg.ubicaciones.get(uId) ?? {
        ubicacionId: uId,
        ubicacionNombre: uNombre,
        unidadCalculo,
        preventivas: 0,
        areaTotal: 0,
        insumos: new Map<string, InsumoAgg>(),
      };

      if (unidadCalculo && !ubicAgg.unidadCalculo) {
        ubicAgg.unidadCalculo = unidadCalculo;
      } else if (
        unidadCalculo &&
        ubicAgg.unidadCalculo &&
        ubicAgg.unidadCalculo !== unidadCalculo
      ) {
        ubicAgg.unidadCalculo = "MIXTA";
      }

      ubicAgg.preventivas += 1;
      ubicAgg.areaTotal += area;
      conjAgg.ubicaciones.set(uId, ubicAgg);
      conjuntos.set(cId, conjAgg);

      totalPreventivas += 1;
      totalArea += area;

      const planInsumos = parsePlanInsumos(d.insumosPlanJson);
      const insumosDef: PlanInsumoItem[] = [...planInsumos];

      const consumoPrincipalPorUnidad = toNumberSafe(d.consumoPrincipalPorUnidad);
      if (d.insumoPrincipalId != null && d.insumoPrincipalId > 0) {
        if (consumoPrincipalPorUnidad > 0) {
          insumosDef.push({
            insumoId: d.insumoPrincipalId,
            consumoPorUnidad: consumoPrincipalPorUnidad,
          });
        }
      }

      for (const it of insumosDef) {
        const info = insumoInfo.get(it.insumoId);
        const nombre = toStringSafe(info?.nombre, `Insumo ${it.insumoId}`);
        const unidad = toStringSafe(info?.unidad, "UND");
        const consumoEstimado = calcConsumoEstimado(area, it.consumoPorUnidad);
        const rendimiento = calcRendimientoInsumo(area, consumoEstimado);
        const key = makeInsumoKey(it.insumoId, nombre, unidad);

        pushInsumoAgg(ubicAgg.insumos, {
          key,
          insumoId: it.insumoId,
          nombre,
          unidad,
          consumoEstimado,
          consumoPorUnidad: it.consumoPorUnidad,
          rendimiento,
        });
        pushInsumoAgg(conjAgg.insumos, {
          key,
          insumoId: it.insumoId,
          nombre,
          unidad,
          consumoEstimado,
          consumoPorUnidad: it.consumoPorUnidad,
          rendimiento,
        });
        pushInsumoAgg(topGlobal, {
          key,
          insumoId: it.insumoId,
          nombre,
          unidad,
          consumoEstimado,
          consumoPorUnidad: it.consumoPorUnidad,
          rendimiento,
        });
      }
    }

    const data = Array.from(conjuntos.values())
      .map((c) => {
        const ubicaciones = Array.from(c.ubicaciones.values())
          .map((u) => {
            const topInsumos = Array.from(u.insumos.values())
              .sort((a, b) => b.consumoEstimado - a.consumoEstimado)
              .map(toOutInsumoRow);

            return {
              ubicacionId: u.ubicacionId,
              ubicacionNombre: u.ubicacionNombre,
              unidadCalculo: u.unidadCalculo,
              preventivas: u.preventivas,
              areaTotal: Number(u.areaTotal.toFixed(4)),
              topInsumos: topInsumos.slice(0, 5),
            };
          })
          .sort((a, b) => b.areaTotal - a.areaTotal);

        const topInsumosConjunto = Array.from(c.insumos.values())
          .sort((a, b) => b.consumoEstimado - a.consumoEstimado)
          .map(toOutInsumoRow)
          .slice(0, 10);

        return {
          conjuntoId: c.conjuntoId,
          conjuntoNombre: c.conjuntoNombre,
          preventivas: c.preventivas,
          ubicaciones: ubicaciones.length,
          areaTotal: Number(c.areaTotal.toFixed(4)),
          ubicacionesDetalle: ubicaciones,
          topInsumos: topInsumosConjunto,
        };
      })
      .sort((a, b) => b.areaTotal - a.areaTotal);

    const topInsumosGlobal = Array.from(topGlobal.values())
      .sort((a, b) => b.consumoEstimado - a.consumoEstimado)
      .map(toOutInsumoRow)
      .slice(0, 15);

    const totalUbicaciones = data.reduce((acc, c) => acc + c.ubicaciones, 0);

    return {
      ok: true,
      resumen: {
        conjuntos: data.length,
        ubicaciones: totalUbicaciones,
        preventivas: totalPreventivas,
        areaTotal: Number(totalArea.toFixed(4)),
        soloActivas,
      },
      topInsumosGlobal,
      data,
    };
  }
}
