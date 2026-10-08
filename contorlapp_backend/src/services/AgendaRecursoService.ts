// src/services/AgendaRecursoService.ts
import type { Prisma, PrismaClient } from "@prisma/client";
import { z } from "zod";

import { parseNecesidadesHerramienta } from "../utils/herramientaNecesidades";
import { parseNecesidadesMaquinaria } from "../utils/maquinariaNecesidades";
import {
  errorNegocio,
  unidadReservable,
  type ClaseRecursoStr,
  type UnidadRecurso,
} from "../utils/recursoAgendaCore";
import { rangosSeSolapan } from "../utils/ventanaRecurso";
import {
  ESTADOS_TAREA_RESERVABLE,
  herramientaItemAUnidad,
  herramientaItemUnidadSelect as unidadHerramientaSelect,
  maquinaAUnidad,
  maquinariaUnidadSelect as unidadMaquinaSelect,
  nombreTipoLegado,
} from "./ReservaRecursoService";

/**
 * Agenda de recursos — lecturas: agenda por unidad, necesidades, alertas,
 * vista por conjunto e historial. Todo se DERIVA de ReservaRecurso y del
 * estado de la unidad; no hay estados duplicados que se desincronicen.
 */

const DIA_MS = 86_400_000;
const MAX_DIAS_RANGO = 93;

export type EstadoDiaRecurso =
  | "DISPONIBLE"
  | "RESERVADO"
  | "EN_TRASLADO"
  | "PRESTADO"
  | "MANTENIMIENTO"
  | "NO_OPERATIVA";

export type EstadoActualRecurso =
  | "DISPONIBLE"
  | "EN_USO"
  | "RESERVADO"
  | "EN_TRASLADO"
  | "PRESTADO"
  | "MANTENIMIENTO"
  | "NO_OPERATIVA";

function inicioDia(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function claveDia(d: Date): string {
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${d.getFullYear()}-${mm}-${dd}`;
}

/**
 * Fechas de consulta. Un "YYYY-MM-DD" es un DÍA del calendario local: si se
 * dejara a `new Date("2026-10-05")` quedaría en UTC medianoche, que en
 * Colombia (UTC-5) es todavía el día 4 y corre toda la agenda un día.
 */
export function parseFechaDia(value: unknown): unknown {
  if (typeof value === "string") {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value.trim());
    if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  }
  return value;
}

const fechaQuery = z.preprocess(parseFechaDia, z.coerce.date());

const RangoDTO = z
  .object({
    desde: fechaQuery,
    hasta: fechaQuery,
  })
  .transform((d) => ({ desde: inicioDia(d.desde), hasta: inicioDia(d.hasta) }))
  .refine((d) => +d.hasta >= +d.desde, {
    message: "La fecha final debe ser igual o posterior a la inicial.",
    path: ["hasta"],
  })
  .refine((d) => (+d.hasta - +d.desde) / DIA_MS <= MAX_DIAS_RANGO, {
    message: `El rango máximo es de ${MAX_DIAS_RANGO} días.`,
    path: ["hasta"],
  });

const boolQuery = z
  .union([z.boolean(), z.string()])
  .optional()
  .transform((v) => v === true || v === "true" || v === "1");

export const AgendaQueryDTO = z.object({
  desde: fechaQuery,
  hasta: fechaQuery,
  q: z.string().trim().max(80).optional(),
  clase: z.enum(["MAQUINARIA", "HERRAMIENTA"]).optional(),
  tipoMaquinariaId: z.coerce.number().int().positive().optional(),
  herramientaId: z.coerce.number().int().positive().optional(),
  unidadId: z.coerce.number().int().positive().optional(),
  conjuntoId: z.string().trim().min(1).optional(),
  estado: z
    .enum(["DISPONIBLE", "RESERVADO", "EN_TRASLADO", "PRESTADO", "MANTENIMIENTO", "NO_OPERATIVA"])
    .optional(),
  propietario: z.enum(["CONJUNTO", "EMPRESA"]).optional(),
  soloConReservas: boolQuery,
  incluirRetiradas: boolQuery,
});

export const NecesidadesQueryDTO = z.object({
  desde: fechaQuery,
  hasta: fechaQuery,
  conjuntoId: z.string().trim().min(1).optional(),
  clase: z.enum(["MAQUINARIA", "HERRAMIENTA"]).optional(),
  cobertura: z.enum(["PENDIENTE", "PARCIAL", "CUBIERTA", "SIN_CUBRIR"]).optional(),
  soloObligatorias: boolQuery,
  q: z.string().trim().max(80).optional(),
});

export const AlertasQueryDTO = z.object({
  desde: fechaQuery.optional(),
  hasta: fechaQuery.optional(),
  conjuntoId: z.string().trim().min(1).optional(),
});

export const SemanaConjuntoQueryDTO = z.object({
  desde: fechaQuery.optional(),
  dias: z.coerce.number().int().min(1).max(31).optional(),
});

export const CapacidadBorradorQueryDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
});

const reservaAgendaSelect = {
  id: true,
  clase: true,
  maquinariaId: true,
  herramientaItemId: true,
  tipo: true,
  estado: true,
  origen: true,
  conjuntoId: true,
  conjuntoNombre: true,
  conjunto: { select: { nombre: true } },
  tareaId: true,
  tareaDescripcion: true,
  necesidadId: true,
  usoInicio: true,
  usoFin: true,
  bloqueoInicio: true,
  bloqueoFin: true,
  observacion: true,
  motivoCancelacion: true,
  recursoEtiqueta: true,
  responsablesJson: true,
  creadoEn: true,
  canceladoEn: true,
  finalizadaEn: true,
  tarea: {
    select: {
      id: true,
      descripcion: true,
      estado: true,
      tipo: true,
      fechaInicio: true,
      fechaFin: true,
      operarios: { select: { id: true, usuario: { select: { nombre: true } } } },
      supervisor: { select: { usuario: { select: { nombre: true } } } },
    },
  },
} satisfies Prisma.ReservaRecursoSelect;

type ReservaAgendaRow = Prisma.ReservaRecursoGetPayload<{ select: typeof reservaAgendaSelect }>;

export type ReservaPublica = {
  id: number;
  clase: ClaseRecursoStr;
  unidadId: number;
  recursoEtiqueta: string;
  tipo: string;
  estado: string;
  origen: string;
  conjuntoId: string | null;
  conjuntoNombre: string | null;
  tareaId: number | null;
  tareaDescripcion: string | null;
  tareaEstado: string | null;
  necesidadId: number | null;
  usoInicio: Date;
  usoFin: Date;
  bloqueoInicio: Date;
  bloqueoFin: Date;
  responsables: string[];
  supervisor: string | null;
  observacion: string | null;
  motivoCancelacion: string | null;
  duracionMinutos: number;
  creadoEn: Date;
  canceladoEn: Date | null;
  finalizadaEn: Date | null;
};

function nombresResponsables(r: ReservaAgendaRow): string[] {
  const vivos = (r.tarea?.operarios ?? [])
    .map((o) => o.usuario?.nombre ?? "")
    .filter((n) => n.trim().length > 0);
  if (vivos.length) return vivos;
  const snap = Array.isArray(r.responsablesJson) ? (r.responsablesJson as any[]) : [];
  return snap.map((s) => String(s?.nombre ?? "")).filter((n) => n.trim().length > 0);
}

export function aReservaPublica(r: ReservaAgendaRow): ReservaPublica {
  return {
    id: r.id,
    clase: r.clase,
    unidadId: (r.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId) ?? 0,
    recursoEtiqueta: r.recursoEtiqueta,
    tipo: r.tipo,
    estado: r.estado,
    origen: r.origen,
    conjuntoId: r.conjuntoId,
    conjuntoNombre: r.conjunto?.nombre ?? r.conjuntoNombre ?? null,
    tareaId: r.tareaId,
    tareaDescripcion: r.tarea?.descripcion ?? r.tareaDescripcion ?? null,
    tareaEstado: r.tarea?.estado ?? null,
    necesidadId: r.necesidadId,
    usoInicio: r.usoInicio,
    usoFin: r.usoFin,
    bloqueoInicio: r.bloqueoInicio,
    bloqueoFin: r.bloqueoFin,
    responsables: nombresResponsables(r),
    supervisor: r.tarea?.supervisor?.usuario?.nombre ?? null,
    observacion: r.observacion,
    motivoCancelacion: r.motivoCancelacion,
    duracionMinutos: Math.round((+r.usoFin - +r.usoInicio) / 60_000),
    creadoEn: r.creadoEn,
    canceladoEn: r.canceladoEn,
    finalizadaEn: r.finalizadaEn,
  };
}

/** Estado de la unidad en un dia, derivado de sus reservas. Prioridad fija. */
export function estadoDelDia(params: {
  dia: Date;
  unidad: UnidadRecurso;
  reservas: Array<Pick<ReservaPublica, "tipo" | "estado" | "usoInicio" | "usoFin" | "bloqueoInicio" | "bloqueoFin" | "conjuntoNombre" | "conjuntoId">>;
}): { estado: EstadoDiaRecurso; conjuntoNombre: string | null; conjuntoId: string | null } {
  const { dia, unidad, reservas } = params;
  const ini = inicioDia(dia);
  const fin = new Date(+ini + DIA_MS);

  const vigentes = reservas.filter((r) => r.estado !== "CANCELADA");
  const mant = vigentes.find(
    (r) => r.tipo === "MANTENIMIENTO" && rangosSeSolapan(ini, fin, r.usoInicio, r.usoFin),
  );
  if (mant) return { estado: "MANTENIMIENTO", conjuntoNombre: null, conjuntoId: null };
  if (!unidadReservable(unidad).ok) return { estado: "NO_OPERATIVA", conjuntoNombre: null, conjuntoId: null };

  const uso = vigentes.find(
    (r) => r.tipo === "TAREA" && rangosSeSolapan(ini, fin, r.usoInicio, r.usoFin),
  );
  if (uso) return { estado: "RESERVADO", conjuntoNombre: uso.conjuntoNombre, conjuntoId: uso.conjuntoId };

  const prestamo = vigentes.find(
    (r) => r.tipo === "PRESTAMO" && rangosSeSolapan(ini, fin, r.bloqueoInicio, r.bloqueoFin),
  );
  if (prestamo) {
    return { estado: "PRESTADO", conjuntoNombre: prestamo.conjuntoNombre, conjuntoId: prestamo.conjuntoId };
  }

  const traslado = vigentes.find(
    (r) => r.tipo === "TAREA" && rangosSeSolapan(ini, fin, r.bloqueoInicio, r.bloqueoFin),
  );
  if (traslado) {
    return { estado: "EN_TRASLADO", conjuntoNombre: traslado.conjuntoNombre, conjuntoId: traslado.conjuntoId };
  }
  return { estado: "DISPONIBLE", conjuntoNombre: null, conjuntoId: null };
}

/** Estado y ubicacion "ahora mismo", y desde cuando vuelve a estar libre. */
export function estadoActualUnidad(params: {
  ahora: Date;
  unidad: UnidadRecurso;
  reservas: ReservaPublica[];
}): {
  estado: EstadoActualRecurso;
  ubicacion: { tipo: "CONJUNTO" | "BODEGA"; conjuntoId: string | null; nombre: string };
  libreDesde: Date | null;
} {
  const { ahora, unidad, reservas } = params;
  const vigentes = reservas.filter((r) => r.estado !== "CANCELADA");
  const base =
    unidad.propietarioTipo === "CONJUNTO"
      ? { tipo: "CONJUNTO" as const, conjuntoId: unidad.conjuntoPropietarioId, nombre: unidad.conjuntoPropietarioNombre ?? "Conjunto" }
      : { tipo: "BODEGA" as const, conjuntoId: null, nombre: "Bodega de la empresa" };

  const contiene = (a: Date, b: Date) => +a <= +ahora && +ahora < +b;
  const actual = vigentes
    .filter((r) => contiene(r.bloqueoInicio, r.bloqueoFin))
    .sort((a, b) => {
      const peso = (t: string) => (t === "MANTENIMIENTO" ? 0 : t === "TAREA" ? 1 : 2);
      return peso(a.tipo) - peso(b.tipo);
    })[0];

  // Libre desde: fin de la cadena de bloqueos que contiene "ahora".
  let libreDesde: Date | null = null;
  if (actual) {
    let fin = actual.bloqueoFin;
    let cambio = true;
    while (cambio) {
      cambio = false;
      for (const r of vigentes) {
        if (+r.bloqueoInicio <= +fin && +r.bloqueoFin > +fin && r.tipo !== "PRESTAMO") {
          fin = r.bloqueoFin;
          cambio = true;
        }
      }
    }
    libreDesde = fin;
  }

  if (!unidadReservable(unidad).ok) {
    return { estado: "NO_OPERATIVA", ubicacion: base, libreDesde: null };
  }
  if (!actual) return { estado: "DISPONIBLE", ubicacion: base, libreDesde: null };

  const ubicacion = actual.conjuntoId
    ? { tipo: "CONJUNTO" as const, conjuntoId: actual.conjuntoId, nombre: actual.conjuntoNombre ?? actual.conjuntoId }
    : base;

  if (actual.tipo === "MANTENIMIENTO") return { estado: "MANTENIMIENTO", ubicacion, libreDesde };
  if (actual.tipo === "PRESTAMO") {
    const usoAhora = vigentes.find((r) => r.tipo === "TAREA" && contiene(r.usoInicio, r.usoFin));
    return { estado: usoAhora ? "EN_USO" : "PRESTADO", ubicacion, libreDesde: actual.bloqueoFin };
  }
  if (contiene(actual.usoInicio, actual.usoFin)) return { estado: "EN_USO", ubicacion, libreDesde };
  return {
    estado: +ahora < +actual.usoInicio ? "EN_TRASLADO" : "RESERVADO",
    ubicacion,
    libreDesde,
  };
}

export class AgendaRecursoService {
  constructor(
    private prisma: PrismaClient,
    private empresaId: string,
  ) {}

  private async nitsEmpresa(): Promise<Set<string>> {
    const rows = await this.prisma.conjunto.findMany({
      where: { empresaId: this.empresaId },
      select: { nit: true },
    });
    return new Set(rows.map((r) => r.nit));
  }

  private async assertConjunto(conjuntoId: string): Promise<{ nit: string; nombre: string }> {
    const c = await this.prisma.conjunto.findFirst({
      where: { nit: conjuntoId, empresaId: this.empresaId },
      select: { nit: true, nombre: true },
    });
    if (!c) throw errorNegocio(404, "El conjunto no existe para esta empresa.");
    return c;
  }

  /* ---------------- unidades ---------------- */

  private async cargarUnidades(filtros: {
    clase?: ClaseRecursoStr;
    tipoMaquinariaId?: number;
    herramientaId?: number;
    unidadId?: number;
    q?: string;
    propietario?: "CONJUNTO" | "EMPRESA";
    conjuntoPropietarioId?: string;
    incluirRetiradas?: boolean;
  }): Promise<UnidadRecurso[]> {
    const empresaScope = [
      { empresaId: this.empresaId },
      { conjuntoPropietario: { empresaId: this.empresaId } },
    ];
    const q = filtros.q?.trim();
    const texto = q ? { contains: q, mode: "insensitive" as const } : undefined;
    const salida: UnidadRecurso[] = [];

    const quiereMaquinas =
      (!filtros.clase || filtros.clase === "MAQUINARIA") && filtros.herramientaId == null;
    const quiereHerramientas =
      (!filtros.clase || filtros.clase === "HERRAMIENTA") && filtros.tipoMaquinariaId == null;

    if (quiereMaquinas) {
      const rows = await this.prisma.maquinaria.findMany({
        where: {
          AND: [
            { OR: empresaScope },
            { estadoAprobacion: "APROBADA" },
            ...(filtros.incluirRetiradas ? [] : [{ retiradoEn: null }, { estado: { not: "RETIRADA" as const } }]),
            ...(filtros.tipoMaquinariaId != null
              ? [
                  {
                    OR: [
                      { tipoCatalogoId: filtros.tipoMaquinariaId },
                      { tipoCatalogo: { fusionadoEnId: filtros.tipoMaquinariaId } },
                    ],
                  },
                ]
              : []),
            ...(filtros.unidadId != null && filtros.clase === "MAQUINARIA" ? [{ id: filtros.unidadId }] : []),
            ...(filtros.propietario ? [{ propietarioTipo: filtros.propietario }] : []),
            ...(filtros.conjuntoPropietarioId ? [{ conjuntoPropietarioId: filtros.conjuntoPropietarioId }] : []),
            ...(texto
              ? [
                  {
                    OR: [
                      { nombre: texto },
                      { codigoInterno: texto },
                      { alias: texto },
                      { marca: texto },
                      { modelo: texto },
                      { serial: texto },
                      { tipoCatalogo: { nombre: texto } },
                    ],
                  },
                ]
              : []),
          ],
        },
        select: unidadMaquinaSelect,
        orderBy: [{ codigoInterno: "asc" }, { id: "asc" }],
        take: 600,
      });
      salida.push(...rows.map(maquinaAUnidad));
    }

    if (quiereHerramientas) {
      const rows = await this.prisma.herramientaItem.findMany({
        where: {
          AND: [
            { OR: empresaScope },
            { estadoAprobacion: "APROBADA" },
            ...(filtros.incluirRetiradas
              ? []
              : [{ retiradoEn: null }, { estado: { notIn: ["RETIRADA" as const, "BAJA" as const] } }]),
            ...(filtros.herramientaId != null
              ? [
                  {
                    OR: [
                      { herramientaId: filtros.herramientaId },
                      { herramienta: { canonicaId: filtros.herramientaId } },
                    ],
                  },
                ]
              : []),
            ...(filtros.unidadId != null && filtros.clase === "HERRAMIENTA" ? [{ id: filtros.unidadId }] : []),
            ...(filtros.propietario ? [{ propietarioTipo: filtros.propietario }] : []),
            ...(filtros.conjuntoPropietarioId ? [{ conjuntoPropietarioId: filtros.conjuntoPropietarioId }] : []),
            ...(texto
              ? [
                  {
                    OR: [
                      { codigoInterno: texto },
                      { alias: texto },
                      { marca: texto },
                      { modelo: texto },
                      { serial: texto },
                      { herramienta: { nombre: texto } },
                    ],
                  },
                ]
              : []),
          ],
        },
        select: unidadHerramientaSelect,
        orderBy: [{ codigoInterno: "asc" }, { id: "asc" }],
        take: 600,
      });
      salida.push(...rows.map(herramientaItemAUnidad));
    }

    // Sin tipo de catalogo, la maquina se agrupa por su tipo legado.
    for (const u of salida) {
      if (u.clase === "MAQUINARIA" && u.tipoId == null && !u.tipoNombre) {
        u.tipoNombre = nombreTipoLegado("OTRO");
      }
    }
    return salida;
  }

  private async reservasDeUnidades(params: {
    unidades: UnidadRecurso[];
    desde: Date;
    hasta: Date;
    incluirCanceladas?: boolean;
  }): Promise<ReservaPublica[]> {
    const maq = params.unidades.filter((u) => u.clase === "MAQUINARIA").map((u) => u.id);
    const herr = params.unidades.filter((u) => u.clase === "HERRAMIENTA").map((u) => u.id);
    if (!maq.length && !herr.length) return [];
    const rows = await this.prisma.reservaRecurso.findMany({
      where: {
        empresaId: this.empresaId,
        OR: [
          ...(maq.length ? [{ maquinariaId: { in: maq } }] : []),
          ...(herr.length ? [{ herramientaItemId: { in: herr } }] : []),
        ],
        ...(params.incluirCanceladas ? {} : { estado: { not: "CANCELADA" as const } }),
        bloqueoInicio: { lt: params.hasta },
        bloqueoFin: { gt: params.desde },
      },
      select: reservaAgendaSelect,
      orderBy: [{ bloqueoInicio: "asc" }, { id: "asc" }],
    });
    return rows.map(aReservaPublica);
  }

  /* ---------------- agenda por unidad ---------------- */

  /**
   * "¿Dónde está y dónde estará cada recurso?". Filas por unidad agrupadas por
   * tipo, con sus reservas del rango, el estado de cada día y la ubicación y
   * disponibilidad actuales.
   */
  async agenda(query: unknown) {
    const dto = AgendaQueryDTO.parse(query);
    const rango = RangoDTO.parse({ desde: dto.desde, hasta: dto.hasta });
    const finExclusivo = new Date(+rango.hasta + DIA_MS);
    if (dto.conjuntoId) await this.assertConjunto(dto.conjuntoId);

    let unidades = await this.cargarUnidades({
      clase: dto.clase,
      tipoMaquinariaId: dto.tipoMaquinariaId,
      herramientaId: dto.herramientaId,
      unidadId: dto.unidadId,
      q: dto.q,
      propietario: dto.propietario,
      incluirRetiradas: dto.incluirRetiradas,
    });

    const ahora = new Date();
    const desdeConsulta = new Date(Math.min(+rango.desde, +ahora - DIA_MS));
    const hastaConsulta = new Date(Math.max(+finExclusivo, +ahora + DIA_MS));
    const reservas = await this.reservasDeUnidades({ unidades, desde: desdeConsulta, hasta: hastaConsulta });
    const porUnidad = new Map<string, ReservaPublica[]>();
    for (const r of reservas) {
      const k = `${r.clase}:${r.unidadId}`;
      (porUnidad.get(k) ?? porUnidad.set(k, []).get(k)!).push(r);
    }

    const dias: Date[] = [];
    for (let d = new Date(rango.desde); +d < +finExclusivo; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
      dias.push(d);
    }

    type Fila = {
      unidad: UnidadRecurso;
      ubicacionBase: string;
      estadoActual: ReturnType<typeof estadoActualUnidad>;
      dias: Array<{ fecha: string; estado: EstadoDiaRecurso; conjuntoId: string | null; conjuntoNombre: string | null }>;
      reservas: ReservaPublica[];
    };

    let filas: Fila[] = unidades.map((unidad) => {
      const todas = porUnidad.get(`${unidad.clase}:${unidad.id}`) ?? [];
      const enRango = todas.filter((r) =>
        rangosSeSolapan(rango.desde, finExclusivo, r.bloqueoInicio, r.bloqueoFin),
      );
      return {
        unidad,
        ubicacionBase:
          unidad.propietarioTipo === "CONJUNTO"
            ? unidad.conjuntoPropietarioNombre ?? "Conjunto"
            : "Bodega de la empresa",
        estadoActual: estadoActualUnidad({ ahora, unidad, reservas: todas }),
        dias: dias.map((dia) => ({ fecha: claveDia(dia), ...estadoDelDia({ dia, unidad, reservas: enRango }) })),
        reservas: enRango,
      };
    });

    if (dto.conjuntoId) {
      const nit = dto.conjuntoId;
      filas = filas.filter(
        (f) =>
          f.unidad.conjuntoPropietarioId === nit || f.reservas.some((r) => r.conjuntoId === nit),
      );
    }
    if (dto.soloConReservas) filas = filas.filter((f) => f.reservas.length > 0);
    if (dto.estado) filas = filas.filter((f) => f.dias.some((d) => d.estado === dto.estado));

    const grupos = new Map<string, { clase: ClaseRecursoStr; tipoId: number | null; tipoNombre: string; unidades: Fila[] }>();
    for (const f of filas) {
      const k = `${f.unidad.clase}:${f.unidad.tipoId ?? f.unidad.tipoNombre}`;
      const g = grupos.get(k) ?? {
        clase: f.unidad.clase,
        tipoId: f.unidad.tipoId,
        tipoNombre: f.unidad.tipoNombre,
        unidades: [],
      };
      g.unidades.push(f);
      grupos.set(k, g);
    }

    const salida = Array.from(grupos.values()).sort((a, b) =>
      a.clase === b.clase ? a.tipoNombre.localeCompare(b.tipoNombre, "es") : a.clase === "MAQUINARIA" ? -1 : 1,
    );
    for (const g of salida) {
      g.unidades.sort((a, b) => a.unidad.etiqueta.localeCompare(b.unidad.etiqueta, "es", { numeric: true }));
    }

    return {
      desde: claveDia(rango.desde),
      hasta: claveDia(rango.hasta),
      dias: dias.map(claveDia),
      totalUnidades: filas.length,
      grupos: salida.map((g) => ({
        clase: g.clase,
        tipoId: g.tipoId,
        tipoNombre: g.tipoNombre,
        total: g.unidades.length,
        disponiblesHoy: g.unidades.filter((u) => u.estadoActual.estado === "DISPONIBLE").length,
        unidades: g.unidades.map((f) => ({
          ...f.unidad,
          reservable: unidadReservable(f.unidad).ok,
          ubicacionBase: f.ubicacionBase,
          estadoActual: f.estadoActual.estado,
          ubicacionActual: f.estadoActual.ubicacion,
          libreDesde: f.estadoActual.libreDesde,
          dias: f.dias,
          reservas: f.reservas,
        })),
      })),
    };
  }

  /* ---------------- necesidades ---------------- */

  async necesidades(query: unknown) {
    const dto = NecesidadesQueryDTO.parse(query);
    const rango = RangoDTO.parse({ desde: dto.desde, hasta: dto.hasta });
    const finExclusivo = new Date(+rango.hasta + DIA_MS);
    const nits = await this.nitsEmpresa();
    if (dto.conjuntoId && !nits.has(dto.conjuntoId)) {
      throw errorNegocio(404, "El conjunto no existe para esta empresa.");
    }
    const q = dto.q?.trim();

    const rows = await this.prisma.necesidadRecursoTarea.findMany({
      where: {
        ...(dto.clase ? { clase: dto.clase } : {}),
        ...(dto.soloObligatorias ? { obligatorio: true } : {}),
        tarea: {
          conjuntoId: dto.conjuntoId ? dto.conjuntoId : { in: Array.from(nits) },
          borrador: false,
          fechaInicio: { gte: rango.desde, lt: finExclusivo },
          ...(q ? { descripcion: { contains: q, mode: "insensitive" as const } } : {}),
        },
      },
      select: {
        id: true,
        clase: true,
        cantidad: true,
        obligatorio: true,
        origen: true,
        tipoMaquinariaId: true,
        herramientaId: true,
        tipoMaquinaria: { select: { nombre: true } },
        herramienta: { select: { nombre: true } },
        tarea: {
          select: {
            id: true,
            descripcion: true,
            estado: true,
            tipo: true,
            fechaInicio: true,
            fechaFin: true,
            grupoPlanId: true,
            conjuntoId: true,
            conjunto: { select: { nombre: true } },
            operarios: { select: { usuario: { select: { nombre: true } } } },
            ubicacion: { select: { nombre: true } },
          },
        },
        reservas: {
          where: { estado: { not: "CANCELADA" } },
          select: reservaAgendaSelect,
          orderBy: { id: "asc" },
        },
      },
      orderBy: [{ tarea: { fechaInicio: "asc" } }, { id: "asc" }],
    });

    const unidadesNoOperativas = await this.unidadesNoReservablesDe(
      rows.flatMap((r) => r.reservas.map(aReservaPublica)),
    );

    let necesidades = rows.map((n) => {
      const reservas = n.reservas.map(aReservaPublica);
      const asignadas = reservas.filter((r) => r.tipo === "TAREA").length;
      const pendientes = Math.max(0, n.cantidad - asignadas);
      const tareaActiva = (ESTADOS_TAREA_RESERVABLE as readonly string[]).includes(n.tarea.estado);
      const conflictos = reservas
        .filter((r) => r.estado === "RESERVADA" && unidadesNoOperativas.has(`${r.clase}:${r.unidadId}`))
        .map((r) => ({
          reservaId: r.id,
          motivo: `${r.recursoEtiqueta} ya no está operativa.`,
        }));
      return {
        id: n.id,
        clase: n.clase,
        tipoId: (n.clase === "MAQUINARIA" ? n.tipoMaquinariaId : n.herramientaId) ?? 0,
        tipoNombre:
          n.clase === "MAQUINARIA" ? n.tipoMaquinaria?.nombre ?? "Maquinaria" : n.herramienta?.nombre ?? "Herramienta",
        cantidad: n.cantidad,
        obligatorio: n.obligatorio,
        origen: n.origen,
        asignadas,
        pendientes,
        cobertura: pendientes === 0 ? "CUBIERTA" : asignadas > 0 ? "PARCIAL" : "PENDIENTE",
        asignable: tareaActiva && pendientes > 0,
        conflictos,
        tarea: {
          id: n.tarea.id,
          descripcion: n.tarea.descripcion,
          estado: n.tarea.estado,
          tipo: n.tarea.tipo,
          fechaInicio: n.tarea.fechaInicio,
          fechaFin: n.tarea.fechaFin,
          grupoPlanId: n.tarea.grupoPlanId,
          conjuntoId: n.tarea.conjuntoId,
          conjuntoNombre: n.tarea.conjunto?.nombre ?? n.tarea.conjuntoId,
          ubicacion: n.tarea.ubicacion?.nombre ?? null,
          operarios: n.tarea.operarios.map((o) => o.usuario?.nombre ?? "").filter(Boolean),
        },
        reservas,
      };
    });

    // El resumen describe TODO el periodo (antes del filtro de cobertura),
    // para que "cubiertas" no salga en 0 al ver solo las pendientes.
    const resumen = {
      total: necesidades.length,
      pendientes: necesidades.filter((n) => n.cobertura === "PENDIENTE").length,
      parciales: necesidades.filter((n) => n.cobertura === "PARCIAL").length,
      cubiertas: necesidades.filter((n) => n.cobertura === "CUBIERTA").length,
      conConflicto: necesidades.filter((n) => n.conflictos.length > 0).length,
    };

    if (dto.cobertura === "SIN_CUBRIR") necesidades = necesidades.filter((n) => n.cobertura !== "CUBIERTA");
    else if (dto.cobertura) necesidades = necesidades.filter((n) => n.cobertura === dto.cobertura);

    return { desde: claveDia(rango.desde), hasta: claveDia(rango.hasta), resumen, necesidades };
  }

  private async unidadesNoReservablesDe(reservas: ReservaPublica[]): Promise<Set<string>> {
    const maq = Array.from(new Set(reservas.filter((r) => r.clase === "MAQUINARIA").map((r) => r.unidadId)));
    const herr = Array.from(new Set(reservas.filter((r) => r.clase === "HERRAMIENTA").map((r) => r.unidadId)));
    const salida = new Set<string>();
    if (maq.length) {
      const rows = await this.prisma.maquinaria.findMany({ where: { id: { in: maq } }, select: unidadMaquinaSelect });
      for (const r of rows) if (!unidadReservable(maquinaAUnidad(r)).ok) salida.add(`MAQUINARIA:${r.id}`);
    }
    if (herr.length) {
      const rows = await this.prisma.herramientaItem.findMany({
        where: { id: { in: herr } },
        select: unidadHerramientaSelect,
      });
      for (const r of rows) if (!unidadReservable(herramientaItemAUnidad(r)).ok) salida.add(`HERRAMIENTA:${r.id}`);
    }
    return salida;
  }

  /* ---------------- alertas ---------------- */

  /**
   * Problemas que requieren atención. Se calculan en cada consulta (no se
   * guardan), así nunca quedan desactualizados.
   */
  async alertas(query: unknown) {
    const dto = AlertasQueryDTO.parse(query);
    const hoy = inicioDia(new Date());
    const desde = dto.desde ? inicioDia(dto.desde) : hoy;
    const hasta = dto.hasta ? inicioDia(dto.hasta) : new Date(+hoy + 30 * DIA_MS);
    const rango = RangoDTO.parse({ desde, hasta });
    const finExclusivo = new Date(+rango.hasta + DIA_MS);
    const nits = await this.nitsEmpresa();
    if (dto.conjuntoId && !nits.has(dto.conjuntoId)) {
      throw errorNegocio(404, "El conjunto no existe para esta empresa.");
    }
    const conjuntos = dto.conjuntoId ? [dto.conjuntoId] : Array.from(nits);

    type Alerta = {
      tipo:
        | "NECESIDAD_SIN_CUBRIR"
        | "NECESIDAD_PARCIAL"
        | "NECESIDAD_OPCIONAL_PENDIENTE"
        | "RECURSO_NO_OPERATIVO"
        | "RESERVA_TAREA_INACTIVA"
        | "RESERVA_FUERA_DE_HORARIO";
      severidad: "ALTA" | "MEDIA" | "BAJA";
      mensaje: string;
      fecha: Date;
      conjuntoId: string | null;
      conjuntoNombre: string | null;
      tareaId: number | null;
      necesidadId: number | null;
      reservaId: number | null;
    };
    const alertas: Alerta[] = [];

    const necesidades = await this.necesidades({
      desde: rango.desde,
      hasta: rango.hasta,
      ...(dto.conjuntoId ? { conjuntoId: dto.conjuntoId } : {}),
    });

    for (const n of necesidades.necesidades) {
      // Tareas cerradas o canceladas no generan alertas de cobertura.
      if (!(ESTADOS_TAREA_RESERVABLE as readonly string[]).includes(n.tarea.estado)) continue;
      const diasFaltan = Math.floor((+inicioDia(new Date(n.tarea.fechaInicio)) - +hoy) / DIA_MS);
      if (n.cobertura !== "CUBIERTA") {
        const severidad: Alerta["severidad"] = !n.obligatorio ? "BAJA" : diasFaltan <= 2 ? "ALTA" : "MEDIA";
        alertas.push({
          tipo: !n.obligatorio
            ? "NECESIDAD_OPCIONAL_PENDIENTE"
            : n.cobertura === "PARCIAL"
              ? "NECESIDAD_PARCIAL"
              : "NECESIDAD_SIN_CUBRIR",
          severidad,
          mensaje: `${n.tarea.conjuntoNombre}: "${n.tarea.descripcion}" necesita ${n.pendientes} ${n.tipoNombre} más (${n.asignadas}/${n.cantidad} asignadas).`,
          fecha: n.tarea.fechaInicio,
          conjuntoId: n.tarea.conjuntoId,
          conjuntoNombre: n.tarea.conjuntoNombre,
          tareaId: n.tarea.id,
          necesidadId: n.id,
          reservaId: null,
        });
      }
      for (const c of n.conflictos) {
        alertas.push({
          tipo: "RECURSO_NO_OPERATIVO",
          severidad: "ALTA",
          mensaje: `${n.tarea.conjuntoNombre}: ${c.motivo} Está reservada para "${n.tarea.descripcion}"; cambia la unidad.`,
          fecha: n.tarea.fechaInicio,
          conjuntoId: n.tarea.conjuntoId,
          conjuntoNombre: n.tarea.conjuntoNombre,
          tareaId: n.tarea.id,
          necesidadId: n.id,
          reservaId: c.reservaId,
        });
      }
    }

    // Reservas vigentes cuya tarea ya no se ejecutará o se movió (datos heredados).
    const vigentes = await this.prisma.reservaRecurso.findMany({
      where: {
        empresaId: this.empresaId,
        estado: "RESERVADA",
        tipo: "TAREA",
        conjuntoId: { in: conjuntos },
        usoInicio: { lt: finExclusivo },
        usoFin: { gt: rango.desde },
      },
      select: reservaAgendaSelect,
    });
    for (const row of vigentes) {
      const r = aReservaPublica(row);
      const t = row.tarea;
      if (!t) {
        alertas.push({
          tipo: "RESERVA_TAREA_INACTIVA",
          severidad: "MEDIA",
          mensaje: `${r.recursoEtiqueta} sigue reservada para una tarea que ya no existe. Cancela la reserva para liberarla.`,
          fecha: r.usoInicio,
          conjuntoId: r.conjuntoId,
          conjuntoNombre: r.conjuntoNombre,
          tareaId: null,
          necesidadId: r.necesidadId,
          reservaId: r.id,
        });
        continue;
      }
      if (!(ESTADOS_TAREA_RESERVABLE as readonly string[]).includes(t.estado)) {
        alertas.push({
          tipo: "RESERVA_TAREA_INACTIVA",
          severidad: "MEDIA",
          mensaje: `${r.recursoEtiqueta} sigue reservada para "${t.descripcion}", que está ${t.estado.toLowerCase().replace(/_/g, " ")}.`,
          fecha: r.usoInicio,
          conjuntoId: r.conjuntoId,
          conjuntoNombre: r.conjuntoNombre,
          tareaId: t.id,
          necesidadId: r.necesidadId,
          reservaId: r.id,
        });
      } else if (+r.usoInicio !== +t.fechaInicio || +r.usoFin < +t.fechaFin) {
        alertas.push({
          tipo: "RESERVA_FUERA_DE_HORARIO",
          severidad: "MEDIA",
          mensaje: `La reserva de ${r.recursoEtiqueta} no coincide con el horario actual de "${t.descripcion}". Cambia o vuelve a asignar la unidad.`,
          fecha: r.usoInicio,
          conjuntoId: r.conjuntoId,
          conjuntoNombre: r.conjuntoNombre,
          tareaId: t.id,
          necesidadId: r.necesidadId,
          reservaId: r.id,
        });
      }
    }

    const peso = { ALTA: 0, MEDIA: 1, BAJA: 2 } as const;
    alertas.sort((a, b) => peso[a.severidad] - peso[b.severidad] || +new Date(a.fecha) - +new Date(b.fecha));

    return {
      desde: claveDia(rango.desde),
      hasta: claveDia(rango.hasta),
      resumen: {
        total: alertas.length,
        alta: alertas.filter((a) => a.severidad === "ALTA").length,
        media: alertas.filter((a) => a.severidad === "MEDIA").length,
        baja: alertas.filter((a) => a.severidad === "BAJA").length,
      },
      alertas,
    };
  }

  /* ---------------- vista por conjunto ---------------- */

  /**
   * Lo que el conjunto necesita saber de la semana: sus necesidades, sus
   * recursos propios con su agenda y qué recursos de la empresa llegan y cuándo.
   */
  async semanaConjunto(conjuntoId: string, query: unknown) {
    const dto = SemanaConjuntoQueryDTO.parse(query);
    const conjunto = await this.assertConjunto(conjuntoId);
    const hoy = inicioDia(new Date());
    const base = dto.desde ? inicioDia(dto.desde) : hoy;
    // Por defecto la semana arranca el lunes.
    const desde = dto.desde
      ? base
      : new Date(base.getFullYear(), base.getMonth(), base.getDate() - ((base.getDay() + 6) % 7));
    const dias = dto.dias ?? 7;
    const hasta = new Date(desde.getFullYear(), desde.getMonth(), desde.getDate() + dias - 1);

    const [necesidades, propios] = await Promise.all([
      this.necesidades({ desde, hasta, conjuntoId }),
      this.agenda({ desde, hasta, conjuntoId }),
    ]);

    const unidadesPropias = propios.grupos.flatMap((g) =>
      g.unidades.filter((u) => u.conjuntoPropietarioId === conjuntoId).map((u) => ({ ...u, tipoNombre: g.tipoNombre })),
    );

    // Recursos de la empresa que llegan a este conjunto en el rango.
    const finExclusivo = new Date(+hasta + DIA_MS);
    const externas = await this.prisma.reservaRecurso.findMany({
      where: {
        empresaId: this.empresaId,
        conjuntoId,
        origen: "EMPRESA",
        tipo: { in: ["TAREA", "PRESTAMO"] },
        estado: { not: "CANCELADA" },
        bloqueoInicio: { lt: finExclusivo },
        bloqueoFin: { gt: desde },
      },
      select: reservaAgendaSelect,
      orderBy: [{ usoInicio: "asc" }, { id: "asc" }],
    });

    const llegadas = new Map<string, ReservaPublica[]>();
    for (const row of externas) {
      const r = aReservaPublica(row);
      const k = claveDia(r.tipo === "PRESTAMO" ? r.bloqueoInicio : r.usoInicio);
      (llegadas.get(k) ?? llegadas.set(k, []).get(k)!).push(r);
    }

    const diasLista: string[] = [];
    for (let i = 0; i < dias; i++) {
      diasLista.push(claveDia(new Date(desde.getFullYear(), desde.getMonth(), desde.getDate() + i)));
    }

    return {
      conjunto,
      desde: claveDia(desde),
      hasta: claveDia(hasta),
      dias: diasLista,
      necesidades: necesidades.necesidades,
      resumenNecesidades: necesidades.resumen,
      recursosPropios: unidadesPropias,
      recursosEmpresa: Array.from(llegadas.entries())
        .sort(([a], [b]) => a.localeCompare(b))
        .map(([fecha, reservas]) => ({ fecha, reservas })),
    };
  }

  /* ---------------- historial de una unidad ---------------- */

  async historialUnidad(clase: ClaseRecursoStr, unidadId: number) {
    const unidad =
      clase === "MAQUINARIA"
        ? await this.prisma.maquinaria.findFirst({
            where: {
              id: unidadId,
              OR: [{ empresaId: this.empresaId }, { conjuntoPropietario: { empresaId: this.empresaId } }],
            },
            select: unidadMaquinaSelect,
          })
        : await this.prisma.herramientaItem.findFirst({
            where: {
              id: unidadId,
              OR: [{ empresaId: this.empresaId }, { conjuntoPropietario: { empresaId: this.empresaId } }],
            },
            select: unidadHerramientaSelect,
          });
    if (!unidad) throw errorNegocio(404, "La unidad no existe para esta empresa.");
    const u =
      clase === "MAQUINARIA"
        ? maquinaAUnidad(unidad as Prisma.MaquinariaGetPayload<{ select: typeof unidadMaquinaSelect }>)
        : herramientaItemAUnidad(unidad as Prisma.HerramientaItemGetPayload<{ select: typeof unidadHerramientaSelect }>);

    const rows = await this.prisma.reservaRecurso.findMany({
      where: {
        empresaId: this.empresaId,
        ...(clase === "MAQUINARIA" ? { maquinariaId: unidadId } : { herramientaItemId: unidadId }),
      },
      select: reservaAgendaSelect,
      orderBy: [{ usoInicio: "desc" }, { id: "desc" }],
      take: 500,
    });
    const reservas = rows.map(aReservaPublica);
    const finalizadas = reservas.filter((r) => r.estado === "FINALIZADA" && r.tipo === "TAREA");

    return {
      unidad: { ...u, reservable: unidadReservable(u).ok },
      estadoActual: estadoActualUnidad({ ahora: new Date(), unidad: u, reservas }),
      resumen: {
        reservas: reservas.length,
        finalizadas: finalizadas.length,
        canceladas: reservas.filter((r) => r.estado === "CANCELADA").length,
        minutosDeUso: finalizadas.reduce((t, r) => t + r.duracionMinutos, 0),
        conjuntosDistintos: new Set(finalizadas.map((r) => r.conjuntoId).filter(Boolean)).size,
      },
      reservas,
    };
  }

  /* ---------------- capacidad proyectada del borrador ---------------- */

  /**
   * Aviso informativo en el borrador (no reserva nada): por día y tipo,
   * cuántas unidades piden las tareas del borrador frente a cuántas unidades
   * operativas podría usar el conjunto (propias + empresa). No descuenta lo
   * que ya esté reservado por otros conjuntos: es una cota superior.
   */
  async capacidadBorrador(conjuntoId: string, query: unknown) {
    const dto = CapacidadBorradorQueryDTO.parse(query);
    await this.assertConjunto(conjuntoId);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: dto.anio,
        periodoMes: dto.mes,
      },
      select: { id: true, fechaInicio: true, maquinariaPlanJson: true, herramientasPlanJson: true },
    });

    const tiposCatalogo = await this.prisma.tipoMaquinariaCatalogo.findMany({
      where: { empresaId: this.empresaId },
      select: { id: true, nombre: true, tipoLegacy: true, fusionadoEnId: true },
    });
    const porLegado = new Map<string, number>();
    for (const t of tiposCatalogo.sort((a, b) => a.id - b.id)) {
      if (t.tipoLegacy && !porLegado.has(t.tipoLegacy)) porLegado.set(t.tipoLegacy, t.fusionadoEnId ?? t.id);
    }
    const nombreTipo = new Map(tiposCatalogo.map((t) => [t.id, t.nombre]));
    const fusion = new Map(tiposCatalogo.map((t) => [t.id, t.fusionadoEnId ?? t.id]));

    // dia|clase|tipo -> cantidad pedida
    const pedido = new Map<string, number>();
    for (const t of tareas) {
      const dia = claveDia(t.fechaInicio);
      for (const n of parseNecesidadesMaquinaria(t.maquinariaPlanJson)) {
        const tipoId =
          n.tipoCatalogoId != null ? fusion.get(n.tipoCatalogoId) ?? n.tipoCatalogoId : n.tipo ? porLegado.get(n.tipo) : undefined;
        if (tipoId == null) continue;
        const k = `${dia}|MAQUINARIA|${tipoId}`;
        pedido.set(k, (pedido.get(k) ?? 0) + n.cantidad);
      }
      for (const n of parseNecesidadesHerramienta(t.herramientasPlanJson)) {
        const k = `${dia}|HERRAMIENTA|${n.herramientaId}`;
        pedido.set(k, (pedido.get(k) ?? 0) + n.cantidad);
      }
    }

    const unidades = await this.cargarUnidades({});
    const capacidad = new Map<string, number>();
    const nombres = new Map<string, string>();
    for (const u of unidades) {
      if (!unidadReservable(u).ok) continue;
      if (u.propietarioTipo === "CONJUNTO" && u.conjuntoPropietarioId !== conjuntoId) continue;
      const k = `${u.clase}|${u.tipoId}`;
      capacidad.set(k, (capacidad.get(k) ?? 0) + 1);
      nombres.set(k, u.tipoNombre);
    }
    const herramientas = await this.prisma.herramienta.findMany({
      where: { empresaId: this.empresaId },
      select: { id: true, nombre: true },
    });
    const nombreHerramienta = new Map(herramientas.map((h) => [h.id, h.nombre]));

    const dias = Array.from(pedido.entries()).map(([k, cantidad]) => {
      const [fecha, clase, tipo] = k.split("|");
      const tipoId = Number(tipo);
      const cap = capacidad.get(`${clase}|${tipoId}`) ?? 0;
      return {
        fecha,
        clase: clase as ClaseRecursoStr,
        tipoId,
        tipoNombre:
          nombres.get(`${clase}|${tipoId}`) ??
          (clase === "MAQUINARIA" ? nombreTipo.get(tipoId) : nombreHerramienta.get(tipoId)) ??
          "Recurso",
        requeridas: cantidad,
        capacidad: cap,
        insuficiente: cantidad > cap,
      };
    });
    dias.sort((a, b) => a.fecha.localeCompare(b.fecha) || a.tipoNombre.localeCompare(b.tipoNombre, "es"));

    return {
      anio: dto.anio,
      mes: dto.mes,
      dias,
      insuficientes: dias.filter((d) => d.insuficiente),
    };
  }
}
