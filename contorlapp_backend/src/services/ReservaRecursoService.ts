// src/services/ReservaRecursoService.ts
import {
  Prisma,
  type ClaseRecurso,
  type PrismaClient,
  type TipoMaquinaria,
} from "@prisma/client";
import { z } from "zod";

import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  type ActorAuditoria,
} from "../model/Auditoria";
import { parseNecesidadesHerramienta } from "../utils/herramientaNecesidades";
import { parseNecesidadesMaquinaria } from "../utils/maquinariaNecesidades";
import {
  aConflictoPublico,
  buildRecursoOcupadoError,
  compararCandidatos,
  errorNegocio,
  evaluarConflictos,
  resolverOrigen,
  unidadReservable,
  type ClaseRecursoStr,
  type ConflictoPublico,
  type GrupoCandidato,
  type OrigenRecursoStr,
  type ReservaLite,
  type TipoReservaStr,
  type UnidadRecurso,
} from "../utils/recursoAgendaCore";
import { getFestivosSet } from "../utils/schedulerUtils";
import {
  calcularVentanaRecurso,
  esErrorExclusionReserva,
  normalizarConfigLogistica,
  normalizarUso,
  rangoConsultaFestivos,
  type ConfigLogisticaRecursos,
  type VentanaRecurso,
} from "../utils/ventanaRecurso";
import { AuditoriaService } from "./AuditoriaService";

/**
 * Agenda de recursos — escritura (reservas) y ganchos de ciclo de vida.
 *
 * Conceptos (ver docs/agenda-recursos.md):
 * - Necesidad (NecesidadRecursoTarea): QUE tipo y cuantas unidades necesita
 *   una tarea publicada. Se crea al publicar; no compromete nada.
 * - Reserva (ReservaRecurso): QUE unidad fisica queda comprometida, cuando y
 *   donde. Nunca se borra: se cancela o se finaliza.
 *
 * La asignacion es manual (decision del negocio): el sistema ordena los
 * candidatos y bloquea los que no sirven, pero una persona elige.
 */

type Db = PrismaClient | Prisma.TransactionClient;

/** Estados de tarea en los que tiene sentido comprometer un recurso. */
export const ESTADOS_TAREA_RESERVABLE = ["ASIGNADA", "EN_PROCESO"] as const;

/** Estados de tarea que liberan (cancelan) sus reservas. */
export const ESTADOS_TAREA_LIBERAN_RECURSOS = [
  "NO_COMPLETADA",
  "PENDIENTE_REPROGRAMACION",
] as const;

/** Estados de tarea que finalizan (cierran) sus reservas. */
export const ESTADOS_TAREA_FINALIZAN_RECURSOS = [
  "COMPLETADA",
  "APROBADA",
  "PENDIENTE_APROBACION",
  "RECHAZADA",
] as const;

const NOMBRE_TIPO_LEGADO: Partial<Record<TipoMaquinaria, string>> = {
  CORTASETOS_MANO: "Cortasetos manual",
  CORTASETOS_ALTURA: "Cortasetos de altura",
  GUADANIA: "Guadaña",
  PODADORA_CESPED: "Podadora de césped",
  HIDROLAVADORA_ELECTRICA: "Hidrolavadora eléctrica",
  HIDROLAVADORA_GASOLINA: "Hidrolavadora a gasolina",
};

export function nombreTipoLegado(tipo: TipoMaquinaria): string {
  return (
    NOMBRE_TIPO_LEGADO[tipo] ??
    tipo
      .toLowerCase()
      .split("_")
      .map((p) => p.charAt(0).toUpperCase() + p.slice(1))
      .join(" ")
  );
}

/** Igual que la normalizacion SQL de la migracion 20260908 (nombreNormalizado). */
export function normalizarNombreCatalogo(nombre: string): string {
  return nombre
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

/* ===================== DTOs ===================== */

const UnidadRefDTO = z.object({
  clase: z.enum(["MAQUINARIA", "HERRAMIENTA"]),
  id: z.coerce.number().int().positive(),
});

export const ReservarDTO = z.object({
  necesidadId: z.coerce.number().int().positive(),
  unidades: z.array(UnidadRefDTO).min(1).max(20),
  aplicarAGrupo: z.boolean().optional().default(false),
  observacion: z.string().trim().max(300).optional(),
});

export const CancelarReservaDTO = z.object({
  motivo: z.string().trim().min(3, "Indica el motivo de la cancelación.").max(300),
});

export const ReemplazarReservaDTO = z.object({
  unidadId: z.coerce.number().int().positive(),
  motivo: z.string().trim().max(300).optional(),
});

export const MantenimientoDTO = z
  .object({
    clase: z.enum(["MAQUINARIA", "HERRAMIENTA"]),
    unidadId: z.coerce.number().int().positive(),
    desde: z.coerce.date(),
    hasta: z.coerce.date(),
    motivo: z.string().trim().min(3, "Indica el motivo del bloqueo.").max(300),
  })
  .refine((d) => +d.hasta > +d.desde, {
    message: "La fecha final del bloqueo debe ser posterior a la inicial.",
    path: ["hasta"],
  });

export const ConfiguracionLogisticaDTO = z.object({
  diasEntregaRecursos: z.array(z.number().int().min(0).max(6)).max(7),
  margenTrasladoMinutos: z.coerce.number().int().min(0).max(1440),
});

/* ===================== Lectura de unidades ===================== */

export const maquinariaUnidadSelect = {
  id: true,
  nombre: true,
  marca: true,
  modelo: true,
  serial: true,
  alias: true,
  codigoInterno: true,
  estado: true,
  estadoAprobacion: true,
  retiradoEn: true,
  propietarioTipo: true,
  conjuntoPropietarioId: true,
  conjuntoPropietario: { select: { nombre: true } },
  tipo: true,
  tipoCatalogoId: true,
  tipoCatalogo: { select: { id: true, nombre: true } },
} satisfies Prisma.MaquinariaSelect;

export const herramientaItemUnidadSelect = {
  id: true,
  codigoInterno: true,
  alias: true,
  marca: true,
  modelo: true,
  serial: true,
  estado: true,
  estadoAprobacion: true,
  retiradoEn: true,
  propietarioTipo: true,
  conjuntoPropietarioId: true,
  conjuntoPropietario: { select: { nombre: true } },
  herramientaId: true,
  herramienta: { select: { id: true, nombre: true, canonicaId: true } },
} satisfies Prisma.HerramientaItemSelect;

function etiquetaUnidad(nombre: string, codigo: string | null, alias: string | null): string {
  const base = (alias ?? "").trim() || nombre.trim();
  return codigo ? `${base} · ${codigo}` : base;
}

export function maquinaAUnidad(
  m: Prisma.MaquinariaGetPayload<{ select: typeof maquinariaUnidadSelect }>,
): UnidadRecurso {
  const tipoNombre = m.tipoCatalogo?.nombre ?? nombreTipoLegado(m.tipo);
  return {
    clase: "MAQUINARIA",
    id: m.id,
    codigo: m.codigoInterno,
    nombre: m.nombre,
    etiqueta: etiquetaUnidad(m.nombre, m.codigoInterno, m.alias),
    alias: m.alias,
    marca: m.marca,
    modelo: m.modelo,
    serial: m.serial,
    tipoId: m.tipoCatalogoId,
    tipoNombre,
    estado: m.estado,
    estadoAprobacion: m.estadoAprobacion,
    retirada: m.retiradoEn != null || m.estado === "RETIRADA",
    propietarioTipo: m.propietarioTipo,
    conjuntoPropietarioId: m.conjuntoPropietarioId,
    conjuntoPropietarioNombre: m.conjuntoPropietario?.nombre ?? null,
  };
}

export function herramientaItemAUnidad(
  h: Prisma.HerramientaItemGetPayload<{ select: typeof herramientaItemUnidadSelect }>,
): UnidadRecurso {
  return {
    clase: "HERRAMIENTA",
    id: h.id,
    codigo: h.codigoInterno,
    nombre: h.herramienta.nombre,
    etiqueta: etiquetaUnidad(h.herramienta.nombre, h.codigoInterno, h.alias),
    alias: h.alias,
    marca: h.marca,
    modelo: h.modelo,
    serial: h.serial,
    tipoId: h.herramienta.canonicaId ?? h.herramientaId,
    tipoNombre: h.herramienta.nombre,
    estado: h.estado,
    estadoAprobacion: h.estadoAprobacion,
    retirada: h.retiradoEn != null || h.estado === "RETIRADA" || h.estado === "BAJA",
    propietarioTipo: h.propietarioTipo,
    conjuntoPropietarioId: h.conjuntoPropietarioId,
    conjuntoPropietarioNombre: h.conjuntoPropietario?.nombre ?? null,
  };
}

/** Ids de herramientas equivalentes (la canonica y sus alias). */
async function idsHerramientaEquivalentes(db: Db, herramientaId: number): Promise<number[]> {
  const h = await db.herramienta.findUnique({
    where: { id: herramientaId },
    select: { id: true, canonicaId: true },
  });
  if (!h) return [herramientaId];
  const canonica = h.canonicaId ?? h.id;
  const aliases = await db.herramienta.findMany({
    where: { canonicaId: canonica },
    select: { id: true },
  });
  return Array.from(new Set([canonica, ...aliases.map((a) => a.id)]));
}

/** Ids de tipos de catalogo equivalentes (el destino y los fusionados en el). */
async function idsTipoMaquinariaEquivalentes(db: Db, tipoId: number): Promise<number[]> {
  const fusionados = await db.tipoMaquinariaCatalogo.findMany({
    where: { fusionadoEnId: tipoId },
    select: { id: true },
  });
  return [tipoId, ...fusionados.map((f) => f.id)];
}

export async function cargarUnidadesDeTipo(params: {
  db: Db;
  empresaId: string;
  clase: ClaseRecursoStr;
  tipoId: number;
}): Promise<UnidadRecurso[]> {
  const { db, empresaId, clase, tipoId } = params;
  if (clase === "MAQUINARIA") {
    const tipos = await idsTipoMaquinariaEquivalentes(db, tipoId);
    const rows = await db.maquinaria.findMany({
      where: {
        tipoCatalogoId: { in: tipos },
        OR: [{ empresaId }, { conjuntoPropietario: { empresaId } }],
      },
      select: maquinariaUnidadSelect,
      orderBy: [{ codigoInterno: "asc" }, { id: "asc" }],
    });
    return rows.map(maquinaAUnidad);
  }
  const ids = await idsHerramientaEquivalentes(db, tipoId);
  const rows = await db.herramientaItem.findMany({
    where: {
      herramientaId: { in: ids },
      OR: [{ empresaId }, { conjuntoPropietario: { empresaId } }],
    },
    select: herramientaItemUnidadSelect,
    orderBy: [{ codigoInterno: "asc" }, { id: "asc" }],
  });
  return rows.map(herramientaItemAUnidad);
}

export async function cargarUnidad(params: {
  db: Db;
  empresaId: string;
  clase: ClaseRecursoStr;
  id: number;
}): Promise<UnidadRecurso | null> {
  const { db, empresaId, clase, id } = params;
  if (clase === "MAQUINARIA") {
    const m = await db.maquinaria.findFirst({
      where: { id, OR: [{ empresaId }, { conjuntoPropietario: { empresaId } }] },
      select: maquinariaUnidadSelect,
    });
    return m ? maquinaAUnidad(m) : null;
  }
  const h = await db.herramientaItem.findFirst({
    where: { id, OR: [{ empresaId }, { conjuntoPropietario: { empresaId } }] },
    select: herramientaItemUnidadSelect,
  });
  return h ? herramientaItemAUnidad(h) : null;
}

/* ===================== Lectura de reservas ===================== */

export const reservaLiteSelect = {
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
} satisfies Prisma.ReservaRecursoSelect;

export function aReservaLite(
  r: Prisma.ReservaRecursoGetPayload<{ select: typeof reservaLiteSelect }>,
): ReservaLite {
  return {
    id: r.id,
    clase: r.clase,
    unidadId: (r.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId) ?? 0,
    tipo: r.tipo,
    estado: r.estado,
    origen: r.origen,
    conjuntoId: r.conjuntoId,
    conjuntoNombre: r.conjunto?.nombre ?? r.conjuntoNombre ?? null,
    tareaId: r.tareaId,
    tareaDescripcion: r.tareaDescripcion,
    necesidadId: r.necesidadId,
    usoInicio: r.usoInicio,
    usoFin: r.usoFin,
    bloqueoInicio: r.bloqueoInicio,
    bloqueoFin: r.bloqueoFin,
  };
}

/** Reservas no canceladas de las unidades cuyo bloqueo cruza [desde, hasta). */
export async function reservasActivasDeUnidades(params: {
  db: Db;
  clase: ClaseRecursoStr;
  unidadIds: number[];
  desde: Date;
  hasta: Date;
}): Promise<Map<number, ReservaLite[]>> {
  const { db, clase, unidadIds, desde, hasta } = params;
  const salida = new Map<number, ReservaLite[]>();
  if (!unidadIds.length) return salida;

  const rows = await db.reservaRecurso.findMany({
    where: {
      clase,
      ...(clase === "MAQUINARIA"
        ? { maquinariaId: { in: unidadIds } }
        : { herramientaItemId: { in: unidadIds } }),
      estado: { not: "CANCELADA" },
      bloqueoInicio: { lt: hasta },
      bloqueoFin: { gt: desde },
    },
    select: reservaLiteSelect,
    orderBy: [{ bloqueoInicio: "asc" }, { id: "asc" }],
  });

  for (const row of rows) {
    const lite = aReservaLite(row);
    const lista = salida.get(lite.unidadId) ?? [];
    lista.push(lite);
    salida.set(lite.unidadId, lista);
  }
  return salida;
}

/* ===================== Configuracion y ventanas ===================== */

export async function cargarConfigLogistica(
  db: Db,
  empresaId: string,
): Promise<ConfigLogisticaRecursos> {
  const empresa = await db.empresa.findUnique({
    where: { nit: empresaId },
    select: { diasEntregaRecursos: true, margenTrasladoMinutos: true },
  });
  return normalizarConfigLogistica(empresa);
}

async function festivosPara(db: Db, inicio: Date, fin: Date): Promise<Set<string>> {
  const rango = rangoConsultaFestivos(inicio, fin);
  return getFestivosSet({
    prisma: db as PrismaClient,
    pais: "CO",
    inicio: rango.inicio,
    fin: rango.fin,
  });
}

/** Calculadora de ventanas con festivos y configuracion ya cargados. */
export async function crearCalculadoraVentanas(params: {
  db: Db;
  empresaId: string;
  desde: Date;
  hasta: Date;
}) {
  const config = await cargarConfigLogistica(params.db, params.empresaId);
  const festivos =
    config.diasEntregaRecursos.length > 0
      ? await festivosPara(params.db, params.desde, params.hasta)
      : new Set<string>();
  return {
    config,
    ventana(origen: OrigenRecursoStr, usoInicio: Date, usoFin: Date): VentanaRecurso {
      return calcularVentanaRecurso({ origen, usoInicio, usoFin, config, festivosSet: festivos });
    },
  };
}

/** Ventana amplia que seguro contiene cualquier bloqueo logistico de un uso. */
function ventanaConsulta(usoInicio: Date, usoFin: Date, margenMin = 0) {
  const pad = Math.max(10 * 24 * 60, margenMin) * 60_000;
  return { desde: new Date(+usoInicio - pad), hasta: new Date(+usoFin + pad) };
}

/* ===================== Necesidades ===================== */

const necesidadSelect = {
  id: true,
  tareaId: true,
  clase: true,
  tipoMaquinariaId: true,
  herramientaId: true,
  cantidad: true,
  obligatorio: true,
  origen: true,
  tipoMaquinaria: { select: { id: true, nombre: true } },
  herramienta: { select: { id: true, nombre: true } },
  tarea: {
    select: {
      id: true,
      descripcion: true,
      fechaInicio: true,
      fechaFin: true,
      estado: true,
      borrador: true,
      tipo: true,
      grupoPlanId: true,
      conjuntoId: true,
      periodoAnio: true,
      periodoMes: true,
      conjunto: { select: { nit: true, nombre: true, empresaId: true } },
    },
  },
  reservas: {
    where: { estado: { not: "CANCELADA" as const }, tipo: "TAREA" as const },
    select: { id: true, maquinariaId: true, herramientaItemId: true, estado: true },
  },
} satisfies Prisma.NecesidadRecursoTareaSelect;

type NecesidadCargada = Prisma.NecesidadRecursoTareaGetPayload<{
  select: typeof necesidadSelect;
}>;

function tipoIdDeNecesidad(n: { clase: ClaseRecurso; tipoMaquinariaId: number | null; herramientaId: number | null }) {
  return (n.clase === "MAQUINARIA" ? n.tipoMaquinariaId : n.herramientaId) ?? 0;
}

function nombreTipoNecesidad(n: NecesidadCargada): string {
  return n.clase === "MAQUINARIA"
    ? n.tipoMaquinaria?.nombre ?? "Maquinaria"
    : n.herramienta?.nombre ?? "Herramienta";
}

/**
 * Crea las NecesidadRecursoTarea de tareas publicadas a partir de sus planes
 * JSON (copiados de la definicion al generar el borrador). Idempotente: no
 * duplica una necesidad que ya existe para la tarea y el tipo.
 *
 * Los planes antiguos traen el enum `tipo`: se resuelve al catalogo de la
 * empresa por `tipoLegacy` (y se crea el tipo si la empresa no lo tiene, igual
 * que hizo la migracion 20260908 con las maquinas).
 */
export async function materializarNecesidadesDeTareas(
  db: Db,
  tareaIds: number[],
): Promise<{ creadas: number; descartadas: Array<{ tareaId: number; motivo: string }> }> {
  const descartadas: Array<{ tareaId: number; motivo: string }> = [];
  if (!tareaIds.length) return { creadas: 0, descartadas };

  const tareas = await db.tarea.findMany({
    where: { id: { in: tareaIds } },
    select: {
      id: true,
      maquinariaPlanJson: true,
      herramientasPlanJson: true,
      conjunto: { select: { empresaId: true } },
    },
  });

  const filas: Prisma.NecesidadRecursoTareaCreateManyInput[] = [];
  const cacheTipoLegado = new Map<string, number>();
  const cacheTipoValido = new Map<string, number | null>();
  const cacheHerramientaValida = new Map<string, number | null>();

  for (const tarea of tareas) {
    const empresaId = tarea.conjunto?.empresaId;
    if (!empresaId) continue;

    const maquinas = new Map<number, { cantidad: number; obligatorio: boolean }>();
    for (const n of parseNecesidadesMaquinaria(tarea.maquinariaPlanJson)) {
      let tipoId: number | null = null;
      if (n.tipoCatalogoId != null) {
        const clave = `${empresaId}|${n.tipoCatalogoId}`;
        if (!cacheTipoValido.has(clave)) {
          const cat = await db.tipoMaquinariaCatalogo.findFirst({
            where: { id: n.tipoCatalogoId, empresaId },
            select: { id: true, fusionadoEnId: true },
          });
          cacheTipoValido.set(clave, cat ? (cat.fusionadoEnId ?? cat.id) : null);
        }
        tipoId = cacheTipoValido.get(clave) ?? null;
      } else if (n.tipo) {
        const clave = `${empresaId}|${n.tipo}`;
        if (!cacheTipoLegado.has(clave)) {
          cacheTipoLegado.set(clave, await resolverTipoLegado(db, empresaId, n.tipo));
        }
        tipoId = cacheTipoLegado.get(clave) ?? null;
      }
      if (tipoId == null) {
        descartadas.push({ tareaId: tarea.id, motivo: "Tipo de maquinaria inexistente en la empresa." });
        continue;
      }
      const previo = maquinas.get(tipoId);
      maquinas.set(tipoId, {
        cantidad: (previo?.cantidad ?? 0) + n.cantidad,
        obligatorio: (previo?.obligatorio ?? false) || n.obligatorio,
      });
    }

    const herramientas = new Map<number, { cantidad: number; obligatorio: boolean }>();
    for (const n of parseNecesidadesHerramienta(tarea.herramientasPlanJson)) {
      const clave = `${empresaId}|${n.herramientaId}`;
      if (!cacheHerramientaValida.has(clave)) {
        const h = await db.herramienta.findFirst({
          where: { id: n.herramientaId, empresaId },
          select: { id: true, canonicaId: true },
        });
        cacheHerramientaValida.set(clave, h ? (h.canonicaId ?? h.id) : null);
      }
      const herramientaId = cacheHerramientaValida.get(clave) ?? null;
      if (herramientaId == null) {
        descartadas.push({ tareaId: tarea.id, motivo: "Herramienta inexistente en la empresa." });
        continue;
      }
      const previo = herramientas.get(herramientaId);
      herramientas.set(herramientaId, {
        cantidad: (previo?.cantidad ?? 0) + n.cantidad,
        obligatorio: (previo?.obligatorio ?? false) || n.obligatorio,
      });
    }

    for (const [tipoMaquinariaId, v] of maquinas) {
      filas.push({
        tareaId: tarea.id,
        clase: "MAQUINARIA",
        tipoMaquinariaId,
        cantidad: v.cantidad,
        obligatorio: v.obligatorio,
        origen: "PLAN_PREVENTIVA",
      });
    }
    for (const [herramientaId, v] of herramientas) {
      filas.push({
        tareaId: tarea.id,
        clase: "HERRAMIENTA",
        herramientaId,
        cantidad: v.cantidad,
        obligatorio: v.obligatorio,
        origen: "PLAN_PREVENTIVA",
      });
    }
  }

  if (!filas.length) return { creadas: 0, descartadas };
  const res = await db.necesidadRecursoTarea.createMany({ data: filas, skipDuplicates: true });
  return { creadas: res.count, descartadas };
}

/** Tipo de catalogo de la empresa para un enum legado; lo crea si falta. */
export async function resolverTipoLegado(
  db: Db,
  empresaId: string,
  tipo: TipoMaquinaria,
): Promise<number> {
  const existente = await db.tipoMaquinariaCatalogo.findFirst({
    where: { empresaId, tipoLegacy: tipo },
    select: { id: true, fusionadoEnId: true },
    orderBy: [{ id: "asc" }],
  });
  if (existente) return existente.fusionadoEnId ?? existente.id;

  const nombre = nombreTipoLegado(tipo);
  const nombreNormalizado = normalizarNombreCatalogo(nombre);
  const porNombre = await db.tipoMaquinariaCatalogo.findUnique({
    where: { empresaId_nombreNormalizado: { empresaId, nombreNormalizado } },
    select: { id: true, fusionadoEnId: true },
  });
  if (porNombre) return porNombre.fusionadoEnId ?? porNombre.id;

  const creado = await db.tipoMaquinariaCatalogo.create({
    data: {
      empresaId,
      nombre,
      nombreNormalizado,
      tipoLegacy: tipo,
      estadoAprobacion: "APROBADA",
      aprobadoEn: new Date(),
    },
    select: { id: true },
  });
  return creado.id;
}

/* ===================== Servicio ===================== */

export type CandidatoRecurso = {
  clase: ClaseRecursoStr;
  unidadId: number;
  etiqueta: string;
  codigo: string | null;
  tipoNombre: string;
  marca: string | null;
  estado: string;
  propietarioTipo: "EMPRESA" | "CONJUNTO";
  conjuntoPropietarioNombre: string | null;
  grupo: GrupoCandidato;
  origen: OrigenRecursoStr;
  disponible: boolean;
  motivo: string | null;
  sugerida: boolean;
  yaAsignada: boolean;
  cercaDelConjunto: boolean;
  usosEnPeriodo: number;
  ventana: { bloqueoInicio: string; bloqueoFin: string } | null;
  reservaAnterior: ContextoReserva | null;
  reservaSiguiente: ContextoReserva | null;
};

export type ContextoReserva = {
  reservaId: number;
  tipo: TipoReservaStr;
  conjuntoNombre: string | null;
  tareaDescripcion: string | null;
  usoInicio: string;
  usoFin: string;
  bloqueoInicio: string;
  bloqueoFin: string;
};

function aContexto(r: ReservaLite | undefined): ContextoReserva | null {
  if (!r) return null;
  return {
    reservaId: r.id,
    tipo: r.tipo,
    conjuntoNombre: r.conjuntoNombre,
    tareaDescripcion: r.tareaDescripcion,
    usoInicio: r.usoInicio.toISOString(),
    usoFin: r.usoFin.toISOString(),
    bloqueoInicio: r.bloqueoInicio.toISOString(),
    bloqueoFin: r.bloqueoFin.toISOString(),
  };
}

type FilaReservaNueva = {
  necesidad: NecesidadCargada;
  unidad: UnidadRecurso;
  origen: OrigenRecursoStr;
  ventana: VentanaRecurso;
};

export class ReservaRecursoService {
  constructor(
    private prisma: PrismaClient,
    private empresaId: string,
    private actor?: ActorAuditoria,
  ) {}

  /* ---------- necesidad + candidatos ---------- */

  private async cargarNecesidad(db: Db, necesidadId: number): Promise<NecesidadCargada> {
    const n = await db.necesidadRecursoTarea.findUnique({
      where: { id: necesidadId },
      select: necesidadSelect,
    });
    if (!n || n.tarea.conjunto?.empresaId !== this.empresaId) {
      throw errorNegocio(404, "La necesidad de recurso no existe para esta empresa.");
    }
    return n;
  }

  private validarTareaReservable(n: NecesidadCargada) {
    if (n.tarea.borrador) {
      throw errorNegocio(
        400,
        "La tarea todavía está en borrador. Los recursos se asignan después de publicar el cronograma.",
      );
    }
    if (!(ESTADOS_TAREA_RESERVABLE as readonly string[]).includes(n.tarea.estado)) {
      throw errorNegocio(
        400,
        `La tarea "${n.tarea.descripcion}" está ${n.tarea.estado.toLowerCase().replace(/_/g, " ")} y ya no admite reservas de recursos.`,
      );
    }
    if (!n.tarea.conjuntoId) {
      throw errorNegocio(400, "La tarea no tiene conjunto asociado.");
    }
  }

  /**
   * Candidatos para cubrir una necesidad, ya evaluados y ordenados. Las
   * unidades que no sirven tambien se devuelven (con `disponible:false` y el
   * motivo) para que el usuario entienda por que no puede elegirlas.
   */
  async candidatos(necesidadId: number) {
    const n = await this.cargarNecesidad(this.prisma, necesidadId);
    const conjuntoId = n.tarea.conjuntoId!;
    const { usoInicio, usoFin } = normalizarUso(n.tarea.fechaInicio, n.tarea.fechaFin);

    const unidades = await cargarUnidadesDeTipo({
      db: this.prisma,
      empresaId: this.empresaId,
      clase: n.clase,
      tipoId: tipoIdDeNecesidad(n),
    });

    const calc = await crearCalculadoraVentanas({
      db: this.prisma,
      empresaId: this.empresaId,
      desde: usoInicio,
      hasta: usoFin,
    });
    const consulta = ventanaConsulta(usoInicio, usoFin, calc.config.margenTrasladoMinutos);
    // Contexto antes/despues: dos semanas a cada lado.
    const desdeCtx = new Date(Math.min(+consulta.desde, +usoInicio - 14 * 86_400_000));
    const hastaCtx = new Date(Math.max(+consulta.hasta, +usoFin + 14 * 86_400_000));
    const reservasPorUnidad = await reservasActivasDeUnidades({
      db: this.prisma,
      clase: n.clase,
      unidadIds: unidades.map((u) => u.id),
      desde: desdeCtx,
      hasta: hastaCtx,
    });

    const yaAsignadas = new Set(
      n.reservas.map((r) => (n.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId)),
    );

    const candidatos: CandidatoRecurso[] = unidades.map((unidad) => {
      const reservas = reservasPorUnidad.get(unidad.id) ?? [];
      const origenInfo = resolverOrigen({ unidad, conjuntoId, usoInicio, usoFin, prestamos: reservas });
      const reservable = unidadReservable(unidad);

      let disponible = reservable.ok && origenInfo.permitido;
      let motivo = reservable.motivo ?? origenInfo.motivo;
      let ventana: VentanaRecurso | null = null;

      const yaAsignada = yaAsignadas.has(unidad.id);
      if (yaAsignada) {
        disponible = false;
        motivo = "Ya está asignada a esta necesidad.";
      }

      if (disponible) {
        ventana = calc.ventana(origenInfo.origen, usoInicio, usoFin);
        const conflictos = evaluarConflictos({
          tipo: "TAREA",
          conjuntoId,
          ventana,
          existentes: reservas,
        });
        if (conflictos.length) {
          disponible = false;
          motivo = conflictos[0].motivo;
        }
      }

      const anteriores = reservas.filter((r) => +r.usoFin <= +usoInicio && r.tipo !== "PRESTAMO");
      const siguientes = reservas.filter((r) => +r.usoInicio >= +usoFin && r.tipo !== "PRESTAMO");
      const reservaAnterior = anteriores.sort((a, b) => +b.usoFin - +a.usoFin)[0];
      const reservaSiguiente = siguientes.sort((a, b) => +a.usoInicio - +b.usoInicio)[0];
      const dosDias = 2 * 86_400_000;
      const cercaDelConjunto = reservas.some(
        (r) =>
          r.conjuntoId === conjuntoId &&
          r.tipo === "TAREA" &&
          +r.usoFin >= +usoInicio - dosDias &&
          +r.usoInicio <= +usoFin + dosDias,
      );
      const usosEnPeriodo = reservas.filter((r) => r.tipo === "TAREA").length;

      return {
        clase: unidad.clase,
        unidadId: unidad.id,
        etiqueta: unidad.etiqueta,
        codigo: unidad.codigo,
        tipoNombre: unidad.tipoNombre,
        marca: unidad.marca,
        estado: unidad.estado,
        propietarioTipo: unidad.propietarioTipo,
        conjuntoPropietarioNombre: unidad.conjuntoPropietarioNombre,
        grupo: origenInfo.grupo,
        origen: origenInfo.origen,
        disponible,
        motivo,
        sugerida: false,
        yaAsignada,
        cercaDelConjunto,
        usosEnPeriodo,
        ventana: ventana
          ? { bloqueoInicio: ventana.bloqueoInicio.toISOString(), bloqueoFin: ventana.bloqueoFin.toISOString() }
          : null,
        reservaAnterior: aContexto(reservaAnterior),
        reservaSiguiente: aContexto(reservaSiguiente),
      };
    });

    candidatos.sort(compararCandidatos);
    const primera = candidatos.find((c) => c.disponible);
    if (primera) primera.sugerida = true;

    const asignadas = n.reservas.length;
    const grupo = await this.tareasDelGrupo(this.prisma, n);

    return {
      necesidad: {
        id: n.id,
        clase: n.clase,
        tipoId: tipoIdDeNecesidad(n),
        tipoNombre: nombreTipoNecesidad(n),
        cantidad: n.cantidad,
        obligatorio: n.obligatorio,
        asignadas,
        pendientes: Math.max(0, n.cantidad - asignadas),
      },
      tarea: {
        id: n.tarea.id,
        descripcion: n.tarea.descripcion,
        fechaInicio: n.tarea.fechaInicio,
        fechaFin: n.tarea.fechaFin,
        conjuntoId,
        conjuntoNombre: n.tarea.conjunto?.nombre ?? conjuntoId,
      },
      grupo: {
        tareasConPendiente: grupo.length,
      },
      logistica: calc.config,
      candidatos,
    };
  }

  /** Otras tareas del mismo grupo (bloques) con la misma necesidad sin cubrir. */
  private async tareasDelGrupo(db: Db, n: NecesidadCargada): Promise<NecesidadCargada[]> {
    if (!n.tarea.grupoPlanId) return [];
    const otras = await db.necesidadRecursoTarea.findMany({
      where: {
        id: { not: n.id },
        clase: n.clase,
        ...(n.clase === "MAQUINARIA"
          ? { tipoMaquinariaId: n.tipoMaquinariaId }
          : { herramientaId: n.herramientaId }),
        tarea: {
          grupoPlanId: n.tarea.grupoPlanId,
          conjuntoId: n.tarea.conjuntoId,
          borrador: false,
          estado: { in: [...ESTADOS_TAREA_RESERVABLE] },
        },
      },
      select: necesidadSelect,
      orderBy: { tarea: { fechaInicio: "asc" } },
    });
    return otras.filter((o) => o.reservas.length < o.cantidad);
  }

  /* ---------- reservar ---------- */

  async reservar(payload: unknown) {
    const dto = ReservarDTO.parse(payload);

    const claves = new Set(dto.unidades.map((u) => `${u.clase}:${u.id}`));
    if (claves.size !== dto.unidades.length) {
      throw errorNegocio(400, "Seleccionaste la misma unidad más de una vez.");
    }

    const filasIntentadas: FilaReservaNueva[] = [];
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          // Lock de la necesidad: dos personas no pueden sobre-cubrirla a la vez.
          await tx.$queryRaw`SELECT id FROM "NecesidadRecursoTarea" WHERE id = ${dto.necesidadId} FOR UPDATE`;
          const n = await this.cargarNecesidad(tx, dto.necesidadId);
          this.validarTareaReservable(n);

          if (dto.unidades.some((u) => u.clase !== n.clase)) {
            throw errorNegocio(
              400,
              n.clase === "MAQUINARIA"
                ? "Esta necesidad es de maquinaria: solo admite máquinas."
                : "Esta necesidad es de herramientas: solo admite herramientas.",
            );
          }

          const pendientes = n.cantidad - n.reservas.length;
          if (pendientes <= 0) {
            throw errorNegocio(409, "La necesidad ya está completamente cubierta.");
          }
          if (dto.unidades.length > pendientes) {
            throw errorNegocio(
              400,
              `Esta necesidad solo tiene ${pendientes} unidad(es) pendiente(s) y seleccionaste ${dto.unidades.length}.`,
            );
          }

          const unidades = await this.bloquearYCargarUnidades(tx, n.clase, dto.unidades.map((u) => u.id));
          const tipoNecesidad = tipoIdDeNecesidad(n);
          const tiposValidos =
            n.clase === "MAQUINARIA"
              ? await idsTipoMaquinariaEquivalentes(tx, tipoNecesidad)
              : await idsHerramientaEquivalentes(tx, tipoNecesidad);

          for (const u of unidades) {
            if (u.tipoId == null || !tiposValidos.includes(u.tipoId)) {
              throw errorNegocio(
                400,
                `${u.etiqueta} es de tipo "${u.tipoNombre}" y la tarea necesita "${nombreTipoNecesidad(n)}".`,
              );
            }
            const reservable = unidadReservable(u);
            if (!reservable.ok) {
              throw errorNegocio(409, `${u.etiqueta}: ${reservable.motivo}`, "RECURSO_NO_OPERATIVO");
            }
          }

          const necesidades = [n, ...(dto.aplicarAGrupo ? await this.tareasDelGrupo(tx, n) : [])];
          const fechas = necesidades.flatMap((x) => [x.tarea.fechaInicio, x.tarea.fechaFin]);
          const calc = await crearCalculadoraVentanas({
            db: tx,
            empresaId: this.empresaId,
            desde: new Date(Math.min(...fechas.map((d) => +d))),
            hasta: new Date(Math.max(...fechas.map((d) => +d))),
          });

          const omitidas: Array<{ tareaId: number; unidadId: number; motivo: string }> = [];
          const conflictosPrincipal: ConflictoPublico[] = [];

          for (const nec of necesidades) {
            const esPrincipal = nec.id === n.id;
            const yaEnNecesidad = new Set(
              nec.reservas.map((r) => (nec.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId)),
            );
            let cupo = nec.cantidad - nec.reservas.length;
            const { usoInicio, usoFin } = normalizarUso(nec.tarea.fechaInicio, nec.tarea.fechaFin);
            const consulta = ventanaConsulta(usoInicio, usoFin, calc.config.margenTrasladoMinutos);
            const reservasPorUnidad = await reservasActivasDeUnidades({
              db: tx,
              clase: nec.clase,
              unidadIds: unidades.map((u) => u.id),
              desde: consulta.desde,
              hasta: consulta.hasta,
            });

            for (const unidad of unidades) {
              if (cupo <= 0) break;
              if (yaEnNecesidad.has(unidad.id)) {
                if (esPrincipal) {
                  throw errorNegocio(409, `${unidad.etiqueta} ya está asignada a esta necesidad.`);
                }
                continue;
              }
              const existentes = reservasPorUnidad.get(unidad.id) ?? [];
              const origenInfo = resolverOrigen({
                unidad,
                conjuntoId: nec.tarea.conjuntoId!,
                usoInicio,
                usoFin,
                prestamos: existentes,
              });
              if (!origenInfo.permitido) {
                if (esPrincipal) throw errorNegocio(409, `${unidad.etiqueta}: ${origenInfo.motivo}`);
                omitidas.push({ tareaId: nec.tarea.id, unidadId: unidad.id, motivo: origenInfo.motivo ?? "" });
                continue;
              }
              const ventana = calc.ventana(origenInfo.origen, usoInicio, usoFin);
              // Las filas que este mismo lote ya va a crear tambien cuentan.
              const propias: ReservaLite[] = filasIntentadas
                .filter((f) => f.unidad.id === unidad.id && f.unidad.clase === unidad.clase)
                .map((f, i) => ({
                  id: -(i + 1),
                  clase: unidad.clase,
                  unidadId: unidad.id,
                  tipo: "TAREA",
                  estado: "RESERVADA",
                  origen: f.origen,
                  conjuntoId: f.necesidad.tarea.conjuntoId,
                  conjuntoNombre: f.necesidad.tarea.conjunto?.nombre ?? null,
                  tareaId: f.necesidad.tarea.id,
                  tareaDescripcion: f.necesidad.tarea.descripcion,
                  necesidadId: f.necesidad.id,
                  ...f.ventana,
                }));
              const conflictos = evaluarConflictos({
                tipo: "TAREA",
                conjuntoId: nec.tarea.conjuntoId,
                ventana,
                existentes: [...existentes, ...propias],
              });
              if (conflictos.length) {
                if (esPrincipal) {
                  conflictosPrincipal.push(
                    aConflictoPublico({
                      unidad,
                      tareaId: nec.tarea.id,
                      tareaDescripcion: nec.tarea.descripcion,
                      conflicto: conflictos[0],
                    }),
                  );
                } else {
                  omitidas.push({ tareaId: nec.tarea.id, unidadId: unidad.id, motivo: conflictos[0].motivo });
                }
                continue;
              }
              filasIntentadas.push({ necesidad: nec, unidad, origen: origenInfo.origen, ventana });
              cupo -= 1;
            }
          }

          if (conflictosPrincipal.length) {
            throw buildRecursoOcupadoError({ conflictos: conflictosPrincipal });
          }

          const creadas: Awaited<ReturnType<ReservaRecursoService["insertarReservaTarea"]>>[] = [];
          for (const fila of filasIntentadas) {
            creadas.push(await this.insertarReservaTarea(tx, fila, dto.observacion));
          }

          await new AuditoriaService(tx).registrar({
            modulo: ModuloAuditoria.RECURSOS,
            entidad: EntidadAuditoria.TAREA,
            entidadId: n.tarea.id,
            accion: AccionAuditoria.RESERVAR_RECURSO,
            conjuntoId: n.tarea.conjuntoId,
            empresaId: this.empresaId,
            actor: this.actor,
            descripcion: `Se reservaron ${creadas.length} unidad(es) de ${nombreTipoNecesidad(n)} para '${n.tarea.descripcion}'.`,
            periodoAnio: n.tarea.periodoAnio,
            periodoMes: n.tarea.periodoMes,
            metadataJson: {
              necesidadId: n.id,
              reservas: creadas.map((c) => ({ id: c.id, tareaId: c.tareaId, unidadId: c.unidadId })),
              omitidas,
            },
          });

          return { ok: true as const, reservas: creadas, omitidas };
        },
        { timeout: 20_000 },
      );
    } catch (err) {
      if (esErrorExclusionReserva(err)) {
        throw await this.errorDesdeExclusion(filasIntentadas);
      }
      throw err;
    }
  }

  /** SELECT ... FOR UPDATE de las unidades: serializa contra cambios de estado. */
  private async bloquearYCargarUnidades(
    tx: Prisma.TransactionClient,
    clase: ClaseRecursoStr,
    ids: number[],
  ): Promise<UnidadRecurso[]> {
    if (clase === "MAQUINARIA") {
      await tx.$queryRaw`SELECT id FROM "Maquinaria" WHERE id = ANY(${ids}::int[]) FOR UPDATE`;
    } else {
      await tx.$queryRaw`SELECT id FROM "HerramientaItem" WHERE id = ANY(${ids}::int[]) FOR UPDATE`;
    }
    const unidades: UnidadRecurso[] = [];
    for (const id of ids) {
      const u = await cargarUnidad({ db: tx, empresaId: this.empresaId, clase, id });
      if (!u) throw errorNegocio(404, "Una de las unidades seleccionadas no existe para esta empresa.");
      unidades.push(u);
    }
    return unidades;
  }

  private async insertarReservaTarea(
    tx: Prisma.TransactionClient,
    fila: FilaReservaNueva,
    observacion?: string,
  ) {
    const { necesidad, unidad, origen, ventana } = fila;
    const creada = await tx.reservaRecurso.create({
      data: {
        empresaId: this.empresaId,
        clase: unidad.clase,
        ...(unidad.clase === "MAQUINARIA"
          ? { maquinariaId: unidad.id }
          : { herramientaItemId: unidad.id }),
        tipo: "TAREA",
        estado: "RESERVADA",
        origen,
        conjuntoId: necesidad.tarea.conjuntoId,
        tareaId: necesidad.tarea.id,
        necesidadId: necesidad.id,
        usoInicio: ventana.usoInicio,
        usoFin: ventana.usoFin,
        bloqueoInicio: ventana.bloqueoInicio,
        bloqueoFin: ventana.bloqueoFin,
        recursoEtiqueta: unidad.etiqueta,
        tareaDescripcion: necesidad.tarea.descripcion,
        conjuntoNombre: necesidad.tarea.conjunto?.nombre ?? null,
        observacion: observacion ?? null,
        creadoPorId: this.actor?.id ?? null,
      },
      select: { id: true },
    });
    return {
      id: creada.id,
      tareaId: necesidad.tarea.id,
      necesidadId: necesidad.id,
      clase: unidad.clase,
      unidadId: unidad.id,
      etiqueta: unidad.etiqueta,
      origen,
      usoInicio: ventana.usoInicio,
      usoFin: ventana.usoFin,
      bloqueoInicio: ventana.bloqueoInicio,
      bloqueoFin: ventana.bloqueoFin,
    };
  }

  /**
   * La BD rechazo el solape (otro usuario reservo la misma unidad entre la
   * validacion y la escritura). Se reconstruye el detalle consultando de nuevo.
   */
  private async errorDesdeExclusion(filas: FilaReservaNueva[]) {
    const conflictos: ConflictoPublico[] = [];
    for (const fila of filas) {
      const consulta = ventanaConsulta(fila.ventana.usoInicio, fila.ventana.usoFin);
      const existentes = await reservasActivasDeUnidades({
        db: this.prisma,
        clase: fila.unidad.clase,
        unidadIds: [fila.unidad.id],
        desde: consulta.desde,
        hasta: consulta.hasta,
      });
      const encontrados = evaluarConflictos({
        tipo: "TAREA",
        conjuntoId: fila.necesidad.tarea.conjuntoId,
        ventana: fila.ventana,
        existentes: existentes.get(fila.unidad.id) ?? [],
      });
      if (encontrados.length) {
        conflictos.push(
          aConflictoPublico({
            unidad: fila.unidad,
            tareaId: fila.necesidad.tarea.id,
            tareaDescripcion: fila.necesidad.tarea.descripcion,
            conflicto: encontrados[0],
          }),
        );
      }
    }
    return buildRecursoOcupadoError({
      conflictos,
      mensaje: conflictos.length
        ? undefined
        : "Otra persona acaba de reservar ese recurso en el mismo horario. Actualiza la vista y elige otra unidad.",
    });
  }

  /* ---------- cancelar / reemplazar ---------- */

  async cancelar(reservaId: number, payload: unknown) {
    const dto = CancelarReservaDTO.parse(payload);
    return this.prisma.$transaction(async (tx) => {
      const r = await tx.reservaRecurso.findFirst({
        where: { id: reservaId, empresaId: this.empresaId },
        select: {
          id: true,
          estado: true,
          tipo: true,
          tareaId: true,
          conjuntoId: true,
          recursoEtiqueta: true,
          tareaDescripcion: true,
          tarea: { select: { periodoAnio: true, periodoMes: true } },
        },
      });
      if (!r) throw errorNegocio(404, "La reserva no existe para esta empresa.");
      if (r.estado !== "RESERVADA") {
        throw errorNegocio(
          409,
          r.estado === "CANCELADA"
            ? "La reserva ya estaba cancelada."
            : "La reserva ya finalizó y forma parte del histórico; no se puede cancelar.",
        );
      }
      if (r.tipo === "PRESTAMO") {
        throw errorNegocio(
          400,
          "Los préstamos se cierran registrando la devolución desde el inventario.",
        );
      }

      await tx.reservaRecurso.update({
        where: { id: r.id },
        data: {
          estado: "CANCELADA",
          motivoCancelacion: dto.motivo,
          canceladoPorId: this.actor?.id ?? null,
          canceladoEn: new Date(),
        },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.RECURSOS,
        entidad: EntidadAuditoria.RESERVA_RECURSO,
        entidadId: r.id,
        accion: AccionAuditoria.CANCELAR_RESERVA_RECURSO,
        conjuntoId: r.conjuntoId,
        empresaId: this.empresaId,
        actor: this.actor,
        descripcion: `Se canceló la reserva de ${r.recursoEtiqueta}${r.tareaDescripcion ? ` para '${r.tareaDescripcion}'` : ""}: ${dto.motivo}`,
        periodoAnio: r.tarea?.periodoAnio ?? null,
        periodoMes: r.tarea?.periodoMes ?? null,
        metadataJson: { tareaId: r.tareaId, tipo: r.tipo },
      });

      return { ok: true as const, reservaId: r.id };
    });
  }

  /** Cambia la unidad de una reserva (p. ej. la propia se daño): cancelar + reservar, atomico. */
  async reemplazar(reservaId: number, payload: unknown) {
    const dto = ReemplazarReservaDTO.parse(payload);
    const actual = await this.prisma.reservaRecurso.findFirst({
      where: { id: reservaId, empresaId: this.empresaId },
      select: { id: true, estado: true, tipo: true, clase: true, necesidadId: true },
    });
    if (!actual) throw errorNegocio(404, "La reserva no existe para esta empresa.");
    if (actual.estado !== "RESERVADA" || actual.tipo !== "TAREA" || !actual.necesidadId) {
      throw errorNegocio(409, "Solo se puede cambiar la unidad de una reserva vigente de una tarea.");
    }

    const motivo = dto.motivo?.trim() || "Cambio de unidad";
    const necesidadId = actual.necesidadId;
    const filas: FilaReservaNueva[] = [];
    try {
      return await this.prisma.$transaction(async (tx) => {
        await tx.$queryRaw`SELECT id FROM "NecesidadRecursoTarea" WHERE id = ${necesidadId} FOR UPDATE`;
        await tx.reservaRecurso.update({
          where: { id: actual.id },
          data: {
            estado: "CANCELADA",
            motivoCancelacion: motivo,
            canceladoPorId: this.actor?.id ?? null,
            canceladoEn: new Date(),
          },
        });

        const n = await this.cargarNecesidad(tx, necesidadId);
        this.validarTareaReservable(n);
        const [unidad] = await this.bloquearYCargarUnidades(tx, actual.clase, [dto.unidadId]);
        const tiposValidos =
          n.clase === "MAQUINARIA"
            ? await idsTipoMaquinariaEquivalentes(tx, tipoIdDeNecesidad(n))
            : await idsHerramientaEquivalentes(tx, tipoIdDeNecesidad(n));
        if (unidad.tipoId == null || !tiposValidos.includes(unidad.tipoId)) {
          throw errorNegocio(400, `${unidad.etiqueta} no es del tipo que necesita la tarea.`);
        }
        const reservable = unidadReservable(unidad);
        if (!reservable.ok) throw errorNegocio(409, `${unidad.etiqueta}: ${reservable.motivo}`);
        if (
          n.reservas.some(
            (r) => (n.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId) === unidad.id,
          )
        ) {
          throw errorNegocio(409, `${unidad.etiqueta} ya está asignada a esta necesidad.`);
        }

        const { usoInicio, usoFin } = normalizarUso(n.tarea.fechaInicio, n.tarea.fechaFin);
        const calc = await crearCalculadoraVentanas({ db: tx, empresaId: this.empresaId, desde: usoInicio, hasta: usoFin });
        const consulta = ventanaConsulta(usoInicio, usoFin, calc.config.margenTrasladoMinutos);
        const existentes =
          (await reservasActivasDeUnidades({ db: tx, clase: unidad.clase, unidadIds: [unidad.id], ...consulta })).get(
            unidad.id,
          ) ?? [];
        const origenInfo = resolverOrigen({
          unidad,
          conjuntoId: n.tarea.conjuntoId!,
          usoInicio,
          usoFin,
          prestamos: existentes,
        });
        if (!origenInfo.permitido) throw errorNegocio(409, `${unidad.etiqueta}: ${origenInfo.motivo}`);
        const ventana = calc.ventana(origenInfo.origen, usoInicio, usoFin);
        const conflictos = evaluarConflictos({
          tipo: "TAREA",
          conjuntoId: n.tarea.conjuntoId,
          ventana,
          existentes,
        });
        if (conflictos.length) {
          throw buildRecursoOcupadoError({
            contexto: "CAMBIO_UNIDAD",
            conflictos: [
              aConflictoPublico({
                unidad,
                tareaId: n.tarea.id,
                tareaDescripcion: n.tarea.descripcion,
                conflicto: conflictos[0],
              }),
            ],
          });
        }

        const fila = { necesidad: n, unidad, origen: origenInfo.origen, ventana };
        filas.push(fila);
        const creada = await this.insertarReservaTarea(tx, fila);

        await new AuditoriaService(tx).registrar({
          modulo: ModuloAuditoria.RECURSOS,
          entidad: EntidadAuditoria.RESERVA_RECURSO,
          entidadId: creada.id,
          accion: AccionAuditoria.REEMPLAZAR_RESERVA_RECURSO,
          conjuntoId: n.tarea.conjuntoId,
          empresaId: this.empresaId,
          actor: this.actor,
          descripcion: `Se cambió la unidad de '${n.tarea.descripcion}' por ${unidad.etiqueta}: ${motivo}`,
          periodoAnio: n.tarea.periodoAnio,
          periodoMes: n.tarea.periodoMes,
          metadataJson: { reservaAnteriorId: actual.id, reservaNuevaId: creada.id },
        });

        return { ok: true as const, reservaCanceladaId: actual.id, reserva: creada };
      });
    } catch (err) {
      if (esErrorExclusionReserva(err)) throw await this.errorDesdeExclusion(filas);
      throw err;
    }
  }

  /* ---------- mantenimiento programado ---------- */

  async bloquearMantenimiento(payload: unknown) {
    const dto = MantenimientoDTO.parse(payload);
    try {
      return await this.prisma.$transaction(async (tx) => {
        const [unidad] = await this.bloquearYCargarUnidades(tx, dto.clase, [dto.unidadId]);
        if (unidad.retirada) throw errorNegocio(400, `${unidad.etiqueta} está retirada del inventario.`);

        // Una unidad del conjunto se mantiene "en" su conjunto; una de la
        // empresa, en bodega (conjuntoId null) y bloquea a todos los conjuntos.
        const conjuntoId = unidad.propietarioTipo === "CONJUNTO" ? unidad.conjuntoPropietarioId : null;
        const ventana: VentanaRecurso = {
          usoInicio: dto.desde,
          usoFin: dto.hasta,
          bloqueoInicio: dto.desde,
          bloqueoFin: dto.hasta,
        };
        const existentes =
          (
            await reservasActivasDeUnidades({
              db: tx,
              clase: unidad.clase,
              unidadIds: [unidad.id],
              desde: dto.desde,
              hasta: dto.hasta,
            })
          ).get(unidad.id) ?? [];
        const conflictos = evaluarConflictos({ tipo: "MANTENIMIENTO", conjuntoId, ventana, existentes });
        if (conflictos.length) {
          throw buildRecursoOcupadoError({
            contexto: "MANTENIMIENTO",
            conflictos: conflictos.map((c) => aConflictoPublico({ unidad, conflicto: c })),
            mensaje: `${unidad.etiqueta} tiene reservas en ese periodo. Cancélalas o cambia la unidad de esas tareas antes de bloquearla.`,
          });
        }

        const creada = await tx.reservaRecurso.create({
          data: {
            empresaId: this.empresaId,
            clase: unidad.clase,
            ...(unidad.clase === "MAQUINARIA" ? { maquinariaId: unidad.id } : { herramientaItemId: unidad.id }),
            tipo: "MANTENIMIENTO",
            estado: "RESERVADA",
            origen: unidad.propietarioTipo === "CONJUNTO" ? "CONJUNTO" : "EMPRESA",
            conjuntoId,
            ...ventana,
            recursoEtiqueta: unidad.etiqueta,
            conjuntoNombre: unidad.conjuntoPropietarioNombre,
            observacion: dto.motivo,
            creadoPorId: this.actor?.id ?? null,
          },
          select: { id: true },
        });

        await new AuditoriaService(tx).registrar({
          modulo: ModuloAuditoria.RECURSOS,
          entidad: EntidadAuditoria.RESERVA_RECURSO,
          entidadId: creada.id,
          accion: AccionAuditoria.BLOQUEAR_MANTENIMIENTO,
          conjuntoId,
          empresaId: this.empresaId,
          actor: this.actor,
          descripcion: `Mantenimiento programado de ${unidad.etiqueta}: ${dto.motivo}`,
          metadataJson: { desde: dto.desde.toISOString(), hasta: dto.hasta.toISOString() },
        });

        return { ok: true as const, reservaId: creada.id };
      });
    } catch (err) {
      if (esErrorExclusionReserva(err)) {
        throw buildRecursoOcupadoError({
          conflictos: [],
          contexto: "MANTENIMIENTO",
          mensaje: "La unidad fue reservada por otra persona en ese periodo. Actualiza la agenda.",
        });
      }
      throw err;
    }
  }

  /* ---------- configuracion logistica ---------- */

  async obtenerConfiguracion() {
    return cargarConfigLogistica(this.prisma, this.empresaId);
  }

  /**
   * Cambia los dias de entrega/margen. Aplica a reservas NUEVAS o movidas: las
   * vigentes conservan su ventana (ya se comunico la logistica).
   */
  async actualizarConfiguracion(payload: unknown) {
    const dto = ConfiguracionLogisticaDTO.parse(payload);
    const config = normalizarConfigLogistica(dto);
    await this.prisma.empresa.update({
      where: { nit: this.empresaId },
      data: {
        diasEntregaRecursos: config.diasEntregaRecursos,
        margenTrasladoMinutos: config.margenTrasladoMinutos,
      },
    });
    await new AuditoriaService(this.prisma).registrar({
      modulo: ModuloAuditoria.RECURSOS,
      entidad: EntidadAuditoria.EMPRESA,
      entidadId: this.empresaId,
      accion: AccionAuditoria.CONFIGURAR_LOGISTICA_RECURSOS,
      empresaId: this.empresaId,
      actor: this.actor,
      descripcion: "Se actualizó la configuración logística de recursos.",
      metadataJson: config,
    });
    return config;
  }
}

/* =====================================================================
 * Ganchos de ciclo de vida de la tarea. Se llaman DENTRO de la transaccion
 * del servicio que cambia la tarea, para que tarea y reservas queden siempre
 * consistentes (sin reservas huerfanas).
 * ===================================================================== */

/**
 * Mueve las reservas vigentes de una tarea a sus nuevas fechas (y conjunto).
 * Si alguna unidad no esta libre en el nuevo horario:
 * - sin `liberarOcupadas`: lanza 409 RECURSO_OCUPADO y no cambia nada
 *   (decision del negocio: reprogramar se bloquea);
 * - con `liberarOcupadas` (accion explicita del usuario): cancela esas
 *   reservas con motivo y mueve las demas.
 */
export async function reubicarReservasDeTarea(
  tx: Prisma.TransactionClient,
  params: {
    tareaId: number;
    fechaInicio: Date;
    fechaFin: Date;
    conjuntoId?: string | null;
    liberarOcupadas?: boolean;
    actor?: ActorAuditoria;
  },
): Promise<{ movidas: number; liberadas: Array<{ reservaId: number; etiqueta: string; motivo: string }> }> {
  const reservas = await tx.reservaRecurso.findMany({
    where: { tareaId: params.tareaId, tipo: "TAREA", estado: "RESERVADA" },
    select: {
      id: true,
      empresaId: true,
      clase: true,
      maquinariaId: true,
      herramientaItemId: true,
      conjuntoId: true,
      recursoEtiqueta: true,
      tareaDescripcion: true,
    },
    orderBy: { id: "asc" },
  });
  if (!reservas.length) return { movidas: 0, liberadas: [] };

  const empresaId = reservas[0].empresaId;
  const conjuntoDestino = params.conjuntoId ?? reservas[0].conjuntoId!;
  const { usoInicio, usoFin } = normalizarUso(params.fechaInicio, params.fechaFin);
  const calc = await crearCalculadoraVentanas({ db: tx, empresaId, desde: usoInicio, hasta: usoFin });
  const consulta = ventanaConsulta(usoInicio, usoFin, calc.config.margenTrasladoMinutos);
  const conjunto = await tx.conjunto.findUnique({
    where: { nit: conjuntoDestino },
    select: { nombre: true },
  });

  const propias = new Set(reservas.map((r) => r.id));
  const planes: Array<{ id: number; ventana: VentanaRecurso; origen: OrigenRecursoStr }> = [];
  const conflictos: ConflictoPublico[] = [];
  const aLiberar: Array<{ reservaId: number; etiqueta: string; motivo: string }> = [];

  for (const r of reservas) {
    const unidadId = (r.clase === "MAQUINARIA" ? r.maquinariaId : r.herramientaItemId)!;
    if (r.clase === "MAQUINARIA") {
      await tx.$queryRaw`SELECT id FROM "Maquinaria" WHERE id = ${unidadId} FOR UPDATE`;
    } else {
      await tx.$queryRaw`SELECT id FROM "HerramientaItem" WHERE id = ${unidadId} FOR UPDATE`;
    }
    const unidad = await cargarUnidad({ db: tx, empresaId, clase: r.clase, id: unidadId });
    const etiqueta = unidad?.etiqueta ?? r.recursoEtiqueta;
    const existentes =
      (await reservasActivasDeUnidades({ db: tx, clase: r.clase, unidadIds: [unidadId], ...consulta })).get(unidadId) ??
      [];

    let motivo: string | null = null;
    let conflicto: ConflictoPublico | null = null;
    let origen: OrigenRecursoStr = "EMPRESA";
    let ventana: VentanaRecurso | null = null;

    if (!unidad) {
      motivo = "La unidad ya no existe en el inventario.";
    } else {
      const reservable = unidadReservable(unidad);
      const origenInfo = resolverOrigen({
        unidad,
        conjuntoId: conjuntoDestino,
        usoInicio,
        usoFin,
        prestamos: existentes,
      });
      if (!reservable.ok) motivo = reservable.motivo;
      else if (!origenInfo.permitido) motivo = origenInfo.motivo;
      else {
        origen = origenInfo.origen;
        ventana = calc.ventana(origen, usoInicio, usoFin);
        const encontrados = evaluarConflictos({
          tipo: "TAREA",
          conjuntoId: conjuntoDestino,
          ventana,
          existentes,
          excluirIds: propias,
        });
        if (encontrados.length) {
          motivo = encontrados[0].motivo;
          conflicto = aConflictoPublico({
            unidad,
            reservaId: r.id,
            tareaId: params.tareaId,
            tareaDescripcion: r.tareaDescripcion,
            conflicto: encontrados[0],
          });
        }
      }
    }

    if (motivo) {
      aLiberar.push({ reservaId: r.id, etiqueta, motivo });
      conflictos.push(
        conflicto ?? {
          clase: r.clase,
          unidadId,
          unidadEtiqueta: etiqueta,
          reservaId: r.id,
          tareaId: params.tareaId,
          tareaDescripcion: r.tareaDescripcion,
          tipoSolape: "NO_PERMITIDO",
          motivo: `${etiqueta}: ${motivo}`,
          ocupadoPor: null,
        },
      );
    } else if (ventana) {
      planes.push({ id: r.id, ventana, origen });
    }
  }

  if (aLiberar.length && !params.liberarOcupadas) {
    throw buildRecursoOcupadoError({ conflictos, contexto: "REPROGRAMAR" });
  }

  for (const l of aLiberar) {
    await tx.reservaRecurso.update({
      where: { id: l.reservaId },
      data: {
        estado: "CANCELADA",
        motivoCancelacion: `Liberada al reprogramar la tarea: ${l.motivo}`,
        canceladoPorId: params.actor?.id ?? null,
        canceladoEn: new Date(),
      },
    });
  }

  try {
    for (const p of planes) {
      await tx.reservaRecurso.update({
        where: { id: p.id },
        data: {
          ...p.ventana,
          origen: p.origen,
          conjuntoId: conjuntoDestino,
          conjuntoNombre: conjunto?.nombre ?? null,
        },
      });
    }
  } catch (err) {
    if (esErrorExclusionReserva(err)) {
      throw buildRecursoOcupadoError({
        conflictos: [],
        contexto: "REPROGRAMAR",
        mensaje:
          "Otra persona acaba de reservar uno de los recursos de esta tarea en el nuevo horario. Intenta de nuevo.",
      });
    }
    throw err;
  }

  if (aLiberar.length) {
    await new AuditoriaService(tx).registrar({
      modulo: ModuloAuditoria.RECURSOS,
      entidad: EntidadAuditoria.TAREA,
      entidadId: params.tareaId,
      accion: AccionAuditoria.CANCELAR_RESERVA_RECURSO,
      empresaId,
      conjuntoId: conjuntoDestino,
      actor: params.actor,
      descripcion: `Al reprogramar se liberaron ${aLiberar.length} recurso(s): ${aLiberar.map((l) => l.etiqueta).join(", ")}.`,
      metadataJson: { liberadas: aLiberar },
    });
  }

  return { movidas: planes.length, liberadas: aLiberar };
}

/** Cancela (no borra) las reservas vigentes de tareas canceladas o borradas. */
export async function cancelarReservasDeTareas(
  tx: Db,
  params: { tareaIds: number[]; motivo: string; actor?: ActorAuditoria },
): Promise<number> {
  if (!params.tareaIds.length) return 0;
  const res = await tx.reservaRecurso.updateMany({
    where: { tareaId: { in: params.tareaIds }, estado: "RESERVADA", tipo: "TAREA" },
    data: {
      estado: "CANCELADA",
      motivoCancelacion: params.motivo,
      canceladoPorId: params.actor?.id ?? null,
      canceladoEn: new Date(),
    },
  });
  return res.count;
}

/**
 * Al cerrar la tarea, sus reservas pasan a FINALIZADA con la foto de quien la
 * ejecuto (histórico). La ventana física se conserva: la unidad sigue en el
 * conjunto hasta la recogida programada.
 */
export async function finalizarReservasDeTarea(tx: Db, tareaId: number): Promise<number> {
  const tarea = await tx.tarea.findUnique({
    where: { id: tareaId },
    select: {
      operarios: { select: { id: true, usuario: { select: { nombre: true } } } },
    },
  });
  const responsables = (tarea?.operarios ?? []).map((o) => ({
    operarioId: o.id,
    nombre: o.usuario?.nombre ?? null,
  }));
  const res = await tx.reservaRecurso.updateMany({
    where: { tareaId, estado: "RESERVADA", tipo: "TAREA" },
    data: {
      estado: "FINALIZADA",
      finalizadaEn: new Date(),
      responsablesJson: responsables as unknown as Prisma.InputJsonValue,
    },
  });
  return res.count;
}

/* =====================================================================
 * Integracion con inventario (prestamos largos y estado de la unidad)
 * ===================================================================== */

/**
 * Un prestamo de inventario (MaquinariaConjunto / HerramientaItemConjunto)
 * se refleja como reserva PRESTAMO: ubica la unidad en el conjunto durante el
 * prestamo, bloquea a los demas conjuntos y deja que el conjunto que la tiene
 * la use en sus tareas. Lanza 409 si choca con reservas de otros conjuntos.
 */
export async function registrarPrestamoEnAgenda(
  tx: Prisma.TransactionClient,
  params: {
    empresaId: string;
    clase: ClaseRecursoStr;
    unidadId: number;
    conjuntoId: string;
    desde: Date;
    hasta: Date;
    prestamoId: number;
    actor?: ActorAuditoria;
  },
): Promise<number> {
  const unidad = await cargarUnidad({ db: tx, empresaId: params.empresaId, clase: params.clase, id: params.unidadId });
  if (!unidad) throw errorNegocio(404, "Activo no encontrado.");
  const conjunto = await tx.conjunto.findUnique({ where: { nit: params.conjuntoId }, select: { nombre: true } });
  const { usoInicio, usoFin } = normalizarUso(params.desde, params.hasta);
  const ventana: VentanaRecurso = { usoInicio, usoFin, bloqueoInicio: usoInicio, bloqueoFin: usoFin };

  const existentes =
    (
      await reservasActivasDeUnidades({
        db: tx,
        clase: params.clase,
        unidadIds: [params.unidadId],
        desde: usoInicio,
        hasta: usoFin,
      })
    ).get(params.unidadId) ?? [];
  const conflictos = evaluarConflictos({ tipo: "PRESTAMO", conjuntoId: params.conjuntoId, ventana, existentes });
  if (conflictos.length) {
    throw buildRecursoOcupadoError({
      contexto: "PRESTAR",
      conflictos: conflictos.map((c) => aConflictoPublico({ unidad, conflicto: c })),
      mensaje: `${unidad.etiqueta} tiene reservas en otros conjuntos durante ese préstamo. ${conflictos[0].motivo}`,
    });
  }

  try {
    const r = await tx.reservaRecurso.create({
      data: {
        empresaId: params.empresaId,
        clase: params.clase,
        ...(params.clase === "MAQUINARIA" ? { maquinariaId: params.unidadId } : { herramientaItemId: params.unidadId }),
        tipo: "PRESTAMO",
        estado: "RESERVADA",
        origen: "EMPRESA",
        conjuntoId: params.conjuntoId,
        ...ventana,
        recursoEtiqueta: unidad.etiqueta,
        conjuntoNombre: conjunto?.nombre ?? null,
        observacion: "Préstamo registrado desde el inventario.",
        ...(params.clase === "MAQUINARIA"
          ? { prestamoMaquinariaId: params.prestamoId }
          : { prestamoHerramientaId: params.prestamoId }),
        creadoPorId: params.actor?.id ?? null,
      },
      select: { id: true },
    });
    return r.id;
  } catch (err) {
    if (esErrorExclusionReserva(err)) {
      throw buildRecursoOcupadoError({
        contexto: "PRESTAR",
        conflictos: [],
        mensaje: `${unidad.etiqueta} acaba de ser reservada en otro conjunto para ese periodo.`,
      });
    }
    throw err;
  }
}

/**
 * Al devolver el prestamo, la reserva PRESTAMO se cierra en el momento real de
 * la devolucion (si nunca empezo, se cancela). Queda en el historico.
 */
export async function cerrarPrestamoEnAgenda(
  tx: Prisma.TransactionClient,
  params: { clase: ClaseRecursoStr; prestamoId: number; actor?: ActorAuditoria },
): Promise<void> {
  const r = await tx.reservaRecurso.findFirst({
    where: {
      tipo: "PRESTAMO",
      estado: "RESERVADA",
      ...(params.clase === "MAQUINARIA"
        ? { prestamoMaquinariaId: params.prestamoId }
        : { prestamoHerramientaId: params.prestamoId }),
    },
    select: { id: true, usoInicio: true },
  });
  if (!r) return;
  const ahora = new Date();
  if (+ahora <= +r.usoInicio) {
    await tx.reservaRecurso.update({
      where: { id: r.id },
      data: {
        estado: "CANCELADA",
        motivoCancelacion: "El préstamo se cerró antes de empezar.",
        canceladoPorId: params.actor?.id ?? null,
        canceladoEn: ahora,
      },
    });
    return;
  }
  await tx.reservaRecurso.update({
    where: { id: r.id },
    data: { estado: "FINALIZADA", finalizadaEn: ahora, usoFin: ahora, bloqueoFin: ahora },
  });
}

/** Reservas vigentes de una unidad desde hoy (para avisar al dañarla o retirarla). */
export async function reservasFuturasDeUnidad(
  db: Db,
  params: { clase: ClaseRecursoStr; unidadId: number },
) {
  const rows = await db.reservaRecurso.findMany({
    where: {
      ...(params.clase === "MAQUINARIA" ? { maquinariaId: params.unidadId } : { herramientaItemId: params.unidadId }),
      estado: "RESERVADA",
      tipo: "TAREA",
      usoFin: { gt: new Date() },
    },
    select: reservaLiteSelect,
    orderBy: { usoInicio: "asc" },
  });
  return rows.map((r) => {
    const lite = aReservaLite(r);
    return {
      reservaId: lite.id,
      tareaId: lite.tareaId,
      tareaDescripcion: lite.tareaDescripcion,
      conjuntoNombre: lite.conjuntoNombre,
      usoInicio: lite.usoInicio,
      usoFin: lite.usoFin,
    };
  });
}

/**
 * Correctivas / actividades especiales: quien las crea elige unidades
 * concretas (maquinas y/o herramientas por codigo). Se registra la necesidad
 * (origen MANUAL) y la reserva de cada unidad con las mismas reglas y la misma
 * proteccion de solape que la agenda. Herramientas pedidas solo por tipo y
 * cantidad quedan como necesidad pendiente, para asignarlas desde la agenda.
 *
 * Lanza 409 RECURSO_OCUPADO si alguna unidad no esta libre; como corre dentro
 * de la transaccion que crea la tarea, la tarea tampoco se crea.
 */
export async function reservarRecursosDeTareaManual(
  tx: Prisma.TransactionClient,
  params: {
    empresaId: string;
    tareaId: number;
    maquinariaIds?: number[];
    herramientaItemIds?: number[];
    herramientasPorTipo?: Array<{ herramientaId: number; cantidad: number }>;
    actor?: ActorAuditoria;
  },
): Promise<{ reservas: number; necesidades: number }> {
  const maquinariaIds = Array.from(new Set(params.maquinariaIds ?? []));
  const herramientaItemIds = Array.from(new Set(params.herramientaItemIds ?? []));
  const porTipo = params.herramientasPorTipo ?? [];
  if (!maquinariaIds.length && !herramientaItemIds.length && !porTipo.length) {
    return { reservas: 0, necesidades: 0 };
  }

  const tarea = await tx.tarea.findUnique({
    where: { id: params.tareaId },
    select: {
      id: true,
      descripcion: true,
      fechaInicio: true,
      fechaFin: true,
      conjuntoId: true,
      conjunto: { select: { nombre: true, empresaId: true } },
    },
  });
  if (!tarea?.conjuntoId || tarea.conjunto?.empresaId !== params.empresaId) {
    throw errorNegocio(400, "La tarea no pertenece a un conjunto de la empresa.");
  }
  const conjuntoId = tarea.conjuntoId;
  const { usoInicio, usoFin } = normalizarUso(tarea.fechaInicio, tarea.fechaFin);
  const calc = await crearCalculadoraVentanas({ db: tx, empresaId: params.empresaId, desde: usoInicio, hasta: usoFin });
  const consulta = ventanaConsulta(usoInicio, usoFin, calc.config.margenTrasladoMinutos);

  // Unidades (con lock) agrupadas por tipo.
  const unidades: UnidadRecurso[] = [];
  if (maquinariaIds.length) {
    await tx.$queryRaw`SELECT id FROM "Maquinaria" WHERE id = ANY(${maquinariaIds}::int[]) FOR UPDATE`;
  }
  if (herramientaItemIds.length) {
    await tx.$queryRaw`SELECT id FROM "HerramientaItem" WHERE id = ANY(${herramientaItemIds}::int[]) FOR UPDATE`;
  }
  for (const id of maquinariaIds) {
    const u = await cargarUnidad({ db: tx, empresaId: params.empresaId, clase: "MAQUINARIA", id });
    if (!u) throw errorNegocio(404, "Una de las máquinas seleccionadas no existe para esta empresa.");
    if (u.tipoId == null) {
      const m = await tx.maquinaria.findUnique({ where: { id }, select: { tipo: true } });
      u.tipoId = await resolverTipoLegado(tx, params.empresaId, m!.tipo);
      await tx.maquinaria.update({ where: { id }, data: { tipoCatalogoId: u.tipoId } });
    }
    unidades.push(u);
  }
  for (const id of herramientaItemIds) {
    const u = await cargarUnidad({ db: tx, empresaId: params.empresaId, clase: "HERRAMIENTA", id });
    if (!u) throw errorNegocio(404, "Una de las herramientas seleccionadas no existe para esta empresa.");
    unidades.push(u);
  }

  const conflictos: ConflictoPublico[] = [];
  const filas: Array<{ unidad: UnidadRecurso; origen: OrigenRecursoStr; ventana: VentanaRecurso }> = [];
  for (const unidad of unidades) {
    const reservable = unidadReservable(unidad);
    if (!reservable.ok) throw errorNegocio(409, `${unidad.etiqueta}: ${reservable.motivo}`, "RECURSO_NO_OPERATIVO");
    const existentes =
      (await reservasActivasDeUnidades({ db: tx, clase: unidad.clase, unidadIds: [unidad.id], ...consulta })).get(
        unidad.id,
      ) ?? [];
    const origenInfo = resolverOrigen({ unidad, conjuntoId, usoInicio, usoFin, prestamos: existentes });
    if (!origenInfo.permitido) throw errorNegocio(409, `${unidad.etiqueta}: ${origenInfo.motivo}`);
    const ventana = calc.ventana(origenInfo.origen, usoInicio, usoFin);
    const encontrados = evaluarConflictos({ tipo: "TAREA", conjuntoId, ventana, existentes });
    if (encontrados.length) {
      conflictos.push(
        aConflictoPublico({ unidad, tareaId: tarea.id, tareaDescripcion: tarea.descripcion, conflicto: encontrados[0] }),
      );
      continue;
    }
    filas.push({ unidad, origen: origenInfo.origen, ventana });
  }
  if (conflictos.length) throw buildRecursoOcupadoError({ conflictos });

  // Necesidades: una por tipo (cantidad = unidades elegidas, o la pedida si es mayor).
  const cantidades = new Map<string, { clase: ClaseRecursoStr; tipoId: number; cantidad: number }>();
  for (const f of filas) {
    const k = `${f.unidad.clase}:${f.unidad.tipoId}`;
    const prev = cantidades.get(k);
    cantidades.set(k, { clase: f.unidad.clase, tipoId: f.unidad.tipoId!, cantidad: (prev?.cantidad ?? 0) + 1 });
  }
  for (const h of porTipo) {
    const herr = await tx.herramienta.findFirst({
      where: { id: h.herramientaId, empresaId: params.empresaId },
      select: { id: true, canonicaId: true },
    });
    if (!herr) throw errorNegocio(404, "Una de las herramientas seleccionadas no existe para esta empresa.");
    const tipoId = herr.canonicaId ?? herr.id;
    const k = `HERRAMIENTA:${tipoId}`;
    const prev = cantidades.get(k);
    const pedida = Math.max(1, Math.ceil(h.cantidad));
    cantidades.set(k, { clase: "HERRAMIENTA", tipoId, cantidad: Math.max(prev?.cantidad ?? 0, pedida) });
  }

  const necesidadPorTipo = new Map<string, number>();
  for (const [k, v] of cantidades) {
    const n = await tx.necesidadRecursoTarea.create({
      data: {
        tareaId: tarea.id,
        clase: v.clase,
        ...(v.clase === "MAQUINARIA" ? { tipoMaquinariaId: v.tipoId } : { herramientaId: v.tipoId }),
        cantidad: v.cantidad,
        obligatorio: true,
        origen: "MANUAL",
      },
      select: { id: true },
    });
    necesidadPorTipo.set(k, n.id);
  }

  try {
    for (const f of filas) {
      await tx.reservaRecurso.create({
        data: {
          empresaId: params.empresaId,
          clase: f.unidad.clase,
          ...(f.unidad.clase === "MAQUINARIA" ? { maquinariaId: f.unidad.id } : { herramientaItemId: f.unidad.id }),
          tipo: "TAREA",
          estado: "RESERVADA",
          origen: f.origen,
          conjuntoId,
          tareaId: tarea.id,
          necesidadId: necesidadPorTipo.get(`${f.unidad.clase}:${f.unidad.tipoId}`) ?? null,
          ...f.ventana,
          recursoEtiqueta: f.unidad.etiqueta,
          tareaDescripcion: tarea.descripcion,
          conjuntoNombre: tarea.conjunto?.nombre ?? null,
          creadoPorId: params.actor?.id ?? null,
        },
      });
    }
  } catch (err) {
    if (esErrorExclusionReserva(err)) {
      throw buildRecursoOcupadoError({
        conflictos: [],
        mensaje: "Otra persona acaba de reservar uno de los recursos elegidos en ese horario. Elige otra unidad.",
      });
    }
    throw err;
  }

  return { reservas: filas.length, necesidades: necesidadPorTipo.size };
}

/**
 * Punto unico para cualquier edicion de una tarea: si cambian fechas o
 * conjunto mueve sus reservas (o lanza 409 si el recurso no esta libre), y si
 * cambia el estado las cancela o finaliza. Llamar dentro de la transaccion que
 * actualiza la tarea.
 */
export async function aplicarCambioTareaEnRecursos(
  tx: Prisma.TransactionClient,
  params: {
    tareaId: number;
    antes: { fechaInicio: Date; fechaFin: Date; conjuntoId: string | null; estado?: string | null };
    despues: { fechaInicio: Date; fechaFin: Date; conjuntoId: string | null; estado?: string | null };
    liberarOcupadas?: boolean;
    actor?: ActorAuditoria;
  },
): Promise<{ movidas: number; liberadas: Array<{ reservaId: number; etiqueta: string; motivo: string }> }> {
  const { antes, despues } = params;
  const estadoCambia = despues.estado != null && despues.estado !== antes.estado;

  if (estadoCambia) {
    const estado = despues.estado!;
    if (
      (ESTADOS_TAREA_LIBERAN_RECURSOS as readonly string[]).includes(estado) ||
      (ESTADOS_TAREA_FINALIZAN_RECURSOS as readonly string[]).includes(estado)
    ) {
      await sincronizarReservasConEstadoTarea(tx, {
        tareaId: params.tareaId,
        estado,
        actor: params.actor,
      });
      return { movidas: 0, liberadas: [] };
    }
  }

  const fechasCambian =
    +antes.fechaInicio !== +despues.fechaInicio ||
    +antes.fechaFin !== +despues.fechaFin ||
    (antes.conjuntoId ?? null) !== (despues.conjuntoId ?? null);
  if (!fechasCambian) return { movidas: 0, liberadas: [] };

  if (!despues.conjuntoId) {
    const n = await cancelarReservasDeTareas(tx, {
      tareaIds: [params.tareaId],
      motivo: "La tarea quedó sin conjunto.",
      actor: params.actor,
    });
    return { movidas: 0, liberadas: n ? [{ reservaId: 0, etiqueta: `${n} recurso(s)`, motivo: "sin conjunto" }] : [] };
  }

  return reubicarReservasDeTarea(tx, {
    tareaId: params.tareaId,
    fechaInicio: despues.fechaInicio,
    fechaFin: despues.fechaFin,
    conjuntoId: despues.conjuntoId,
    liberarOcupadas: params.liberarOcupadas,
    actor: params.actor,
  });
}

/**
 * Sincroniza la agenda con un cambio de estado de la tarea: cancela si queda
 * sin ejecutarse y finaliza si se cierra.
 */
export async function sincronizarReservasConEstadoTarea(
  tx: Db,
  params: { tareaId: number; estado: string; actor?: ActorAuditoria },
): Promise<void> {
  if ((ESTADOS_TAREA_LIBERAN_RECURSOS as readonly string[]).includes(params.estado)) {
    await cancelarReservasDeTareas(tx, {
      tareaIds: [params.tareaId],
      motivo: `La tarea pasó a ${params.estado.toLowerCase().replace(/_/g, " ")}.`,
      actor: params.actor,
    });
  } else if ((ESTADOS_TAREA_FINALIZAN_RECURSOS as readonly string[]).includes(params.estado)) {
    await finalizarReservasDeTarea(tx, params.tareaId);
  }
}
