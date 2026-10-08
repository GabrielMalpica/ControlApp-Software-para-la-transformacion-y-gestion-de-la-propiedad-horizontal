// src/utils/recursoAgendaCore.ts
//
// Logica pura de la agenda de recursos (sin Prisma), para poder probarla sin
// base de datos. Las reglas de conflicto replican EXACTAMENTE las restricciones
// de exclusion de ReservaRecurso (migracion 20261008000000_agenda_recursos):
// el servicio las evalua antes de escribir para dar mensajes claros, y la base
// de datos las garantiza aunque dos usuarios reserven a la vez.

import { rangosSeSolapan, type VentanaRecurso } from "./ventanaRecurso";

export type ClaseRecursoStr = "MAQUINARIA" | "HERRAMIENTA";
export type TipoReservaStr = "TAREA" | "PRESTAMO" | "MANTENIMIENTO";
export type EstadoReservaStr = "RESERVADA" | "FINALIZADA" | "CANCELADA";
export type OrigenRecursoStr = "CONJUNTO" | "EMPRESA";

/** Unidad fisica reservable (Maquinaria o HerramientaItem) en forma comun. */
export type UnidadRecurso = {
  clase: ClaseRecursoStr;
  id: number;
  codigo: string | null;
  nombre: string;
  etiqueta: string;
  alias: string | null;
  marca: string | null;
  modelo: string | null;
  serial: string | null;
  /** TipoMaquinariaCatalogo.id (maquinaria) o Herramienta.id (herramienta). */
  tipoId: number | null;
  tipoNombre: string;
  estado: string;
  estadoAprobacion: string;
  retirada: boolean;
  propietarioTipo: "EMPRESA" | "CONJUNTO";
  conjuntoPropietarioId: string | null;
  conjuntoPropietarioNombre: string | null;
};

/** Reserva existente, minima, para evaluar conflictos y contexto. */
export type ReservaLite = {
  id: number;
  clase: ClaseRecursoStr;
  unidadId: number;
  tipo: TipoReservaStr;
  estado: EstadoReservaStr;
  origen: OrigenRecursoStr;
  conjuntoId: string | null;
  conjuntoNombre: string | null;
  tareaId: number | null;
  tareaDescripcion: string | null;
  necesidadId: number | null;
  usoInicio: Date;
  usoFin: Date;
  bloqueoInicio: Date;
  bloqueoFin: Date;
};

export type TipoSolape = "USO" | "UBICACION";

export type ConflictoReserva = {
  tipoSolape: TipoSolape;
  ocupadoPor: ReservaLite;
  motivo: string;
};

export function unidadReservable(unidad: UnidadRecurso): { ok: boolean; motivo: string | null } {
  if (unidad.retirada) return { ok: false, motivo: "Está retirada del inventario." };
  if (unidad.estadoAprobacion !== "APROBADA") {
    return { ok: false, motivo: "Aún no está aprobada en el inventario." };
  }
  if (unidad.estado !== "OPERATIVA") {
    return { ok: false, motivo: `No está operativa (${etiquetaEstado(unidad.estado)}).` };
  }
  return { ok: true, motivo: null };
}

export function etiquetaEstado(estado: string): string {
  switch (estado) {
    case "OPERATIVA":
      return "operativa";
    case "EN_REPARACION":
      return "en reparación";
    case "EN_MANTENIMIENTO":
      return "en mantenimiento";
    case "DANADA":
      return "dañada";
    case "FUERA_DE_SERVICIO":
      return "fuera de servicio";
    case "PERDIDA":
      return "perdida";
    case "BAJA":
      return "dada de baja";
    case "RETIRADA":
      return "retirada";
    default:
      return estado.toLowerCase().replace(/_/g, " ");
  }
}

function fmtFechaHora(d: Date): string {
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const hh = String(d.getHours()).padStart(2, "0");
  const mi = String(d.getMinutes()).padStart(2, "0");
  return `${dd}/${mm} ${hh}:${mi}`;
}

function describirOcupante(r: ReservaLite): string {
  if (r.tipo === "MANTENIMIENTO") return "un bloqueo de mantenimiento";
  const donde = r.conjuntoNombre ?? r.conjuntoId ?? "otro conjunto";
  if (r.tipo === "PRESTAMO") return `un préstamo a ${donde}`;
  const que = r.tareaDescripcion ? `"${r.tareaDescripcion}"` : "otra tarea";
  return `${que} en ${donde}`;
}

/**
 * Conflictos que tendria una reserva nueva (o movida) contra las existentes de
 * la MISMA unidad. Replica las dos restricciones de exclusion:
 *  1. USO: ninguna de las dos es PRESTAMO y los usos se cruzan.
 *  2. UBICACION: conjuntos distintos (null = bodega) y los bloqueos se cruzan.
 * Las reservas CANCELADA y las de `excluirIds` no cuentan.
 */
export function evaluarConflictos(params: {
  tipo: TipoReservaStr;
  conjuntoId: string | null;
  ventana: VentanaRecurso;
  existentes: ReservaLite[];
  excluirIds?: Set<number>;
}): ConflictoReserva[] {
  const { tipo, conjuntoId, ventana, existentes, excluirIds } = params;
  const salida: ConflictoReserva[] = [];

  for (const r of existentes) {
    if (r.estado === "CANCELADA") continue;
    if (excluirIds?.has(r.id)) continue;

    if (
      tipo !== "PRESTAMO" &&
      r.tipo !== "PRESTAMO" &&
      rangosSeSolapan(ventana.usoInicio, ventana.usoFin, r.usoInicio, r.usoFin)
    ) {
      salida.push({
        tipoSolape: "USO",
        ocupadoPor: r,
        motivo: `Ya está en uso por ${describirOcupante(r)} (${fmtFechaHora(r.usoInicio)}–${fmtFechaHora(r.usoFin)}).`,
      });
      continue;
    }

    if (
      (r.conjuntoId ?? "") !== (conjuntoId ?? "") &&
      rangosSeSolapan(ventana.bloqueoInicio, ventana.bloqueoFin, r.bloqueoInicio, r.bloqueoFin)
    ) {
      salida.push({
        tipoSolape: "UBICACION",
        ocupadoPor: r,
        motivo: `Está comprometida con ${describirOcupante(r)} entre ${fmtFechaHora(r.bloqueoInicio)} y ${fmtFechaHora(r.bloqueoFin)} (incluye entrega, recogida o traslado).`,
      });
    }
  }

  return salida;
}

export type GrupoCandidato = "CONJUNTO" | "CUSTODIA" | "EMPRESA";

/**
 * De donde sale la unidad para ir a `conjuntoId`:
 * - propia del conjunto -> CONJUNTO (horas exactas);
 * - de otro conjunto -> no permitido;
 * - de la empresa en custodia (prestamo vigente que cubre el uso) en ese
 *   conjunto -> CONJUNTO / CUSTODIA (ya esta alli, no viaja);
 * - de la empresa -> EMPRESA (viaja: ventana logistica).
 */
export function resolverOrigen(params: {
  unidad: UnidadRecurso;
  conjuntoId: string;
  usoInicio: Date;
  usoFin: Date;
  prestamos: ReservaLite[];
}): {
  permitido: boolean;
  origen: OrigenRecursoStr;
  grupo: GrupoCandidato;
  motivo: string | null;
} {
  const { unidad, conjuntoId, usoInicio, usoFin, prestamos } = params;

  if (unidad.propietarioTipo === "CONJUNTO") {
    if (unidad.conjuntoPropietarioId === conjuntoId) {
      return { permitido: true, origen: "CONJUNTO", grupo: "CONJUNTO", motivo: null };
    }
    return {
      permitido: false,
      origen: "CONJUNTO",
      grupo: "CONJUNTO",
      motivo: `Pertenece a ${unidad.conjuntoPropietarioNombre ?? "otro conjunto"} y no se presta a otros conjuntos.`,
    };
  }

  const enCustodia = prestamos.some(
    (p) =>
      p.tipo === "PRESTAMO" &&
      p.estado !== "CANCELADA" &&
      p.unidadId === unidad.id &&
      p.conjuntoId === conjuntoId &&
      +p.bloqueoInicio <= +usoInicio &&
      +p.bloqueoFin >= +usoFin,
  );
  if (enCustodia) {
    return { permitido: true, origen: "CONJUNTO", grupo: "CUSTODIA", motivo: null };
  }

  return { permitido: true, origen: "EMPRESA", grupo: "EMPRESA", motivo: null };
}

const PESO_GRUPO: Record<GrupoCandidato, number> = {
  CONJUNTO: 0,
  CUSTODIA: 1,
  EMPRESA: 2,
};

export type CandidatoOrdenable = {
  disponible: boolean;
  grupo: GrupoCandidato;
  /** Ya tiene reservas en el mismo conjunto cerca (menos traslados). */
  cercaDelConjunto: boolean;
  usosEnPeriodo: number;
  etiqueta: string;
};

/**
 * Orden de sugerencia: primero las disponibles; dentro, las del conjunto, luego
 * las que estan en custodia alli y al final las de la empresa (regla de
 * preferencia acordada). A igualdad, la que ya esta cerca del conjunto (evita un
 * viaje) y la menos usada en el periodo (reparte el desgaste).
 */
export function compararCandidatos(a: CandidatoOrdenable, b: CandidatoOrdenable): number {
  if (a.disponible !== b.disponible) return a.disponible ? -1 : 1;
  const porGrupo = PESO_GRUPO[a.grupo] - PESO_GRUPO[b.grupo];
  if (porGrupo !== 0) return porGrupo;
  if (a.cercaDelConjunto !== b.cercaDelConjunto) return a.cercaDelConjunto ? -1 : 1;
  if (a.usosEnPeriodo !== b.usosEnPeriodo) return a.usosEnPeriodo - b.usosEnPeriodo;
  return a.etiqueta.localeCompare(b.etiqueta, "es", { numeric: true });
}

export type ConflictoPublico = {
  clase: ClaseRecursoStr;
  unidadId: number;
  unidadEtiqueta: string;
  reservaId: number | null;
  tareaId: number | null;
  tareaDescripcion: string | null;
  tipoSolape: TipoSolape | "NO_PERMITIDO";
  motivo: string;
  ocupadoPor: {
    reservaId: number;
    tipo: TipoReservaStr;
    conjuntoId: string | null;
    conjuntoNombre: string | null;
    tareaId: number | null;
    tareaDescripcion: string | null;
    usoInicio: string;
    usoFin: string;
    bloqueoInicio: string;
    bloqueoFin: string;
  } | null;
};

export function aConflictoPublico(params: {
  unidad: { clase: ClaseRecursoStr; id: number; etiqueta: string };
  reservaId?: number | null;
  tareaId?: number | null;
  tareaDescripcion?: string | null;
  conflicto: ConflictoReserva;
}): ConflictoPublico {
  const { unidad, conflicto } = params;
  const o = conflicto.ocupadoPor;
  return {
    clase: unidad.clase,
    unidadId: unidad.id,
    unidadEtiqueta: unidad.etiqueta,
    reservaId: params.reservaId ?? null,
    tareaId: params.tareaId ?? null,
    tareaDescripcion: params.tareaDescripcion ?? null,
    tipoSolape: conflicto.tipoSolape,
    motivo: `${unidad.etiqueta}: ${conflicto.motivo}`,
    ocupadoPor: {
      reservaId: o.id,
      tipo: o.tipo,
      conjuntoId: o.conjuntoId,
      conjuntoNombre: o.conjuntoNombre,
      tareaId: o.tareaId,
      tareaDescripcion: o.tareaDescripcion,
      usoInicio: o.usoInicio.toISOString(),
      usoFin: o.usoFin.toISOString(),
      bloqueoInicio: o.bloqueoInicio.toISOString(),
      bloqueoFin: o.bloqueoFin.toISOString(),
    },
  };
}

/**
 * Error de negocio 409. Viaja tal cual al cliente (el errorHandler central
 * respeta objetos `{ ok:false, status, message }`), con el detalle de cada
 * conflicto para que el frontend lo muestre.
 */
export function buildRecursoOcupadoError(params: {
  conflictos: ConflictoPublico[];
  contexto?: "RESERVAR" | "REPROGRAMAR" | "PRESTAR" | "MANTENIMIENTO" | "CAMBIO_UNIDAD";
  mensaje?: string;
}) {
  const { conflictos, contexto = "RESERVAR" } = params;
  const primero = conflictos[0];
  const titulo =
    contexto === "REPROGRAMAR"
      ? "La tarea tiene recursos ocupados en la nueva fecha"
      : "El recurso no está disponible";

  const message =
    params.mensaje ??
    (primero
      ? conflictos.length === 1
        ? primero.motivo
        : `${primero.motivo} (y ${conflictos.length - 1} conflicto(s) más).`
      : "El recurso ya está comprometido en ese horario.");

  const userHint =
    contexto === "REPROGRAMAR"
      ? "Puedes liberar los recursos en conflicto y reprogramar, o elegir otra fecha."
      : "Elige otra unidad disponible o revisa la agenda del recurso.";

  return {
    status: 409,
    ok: false as const,
    reason: "RECURSO_OCUPADO" as const,
    code: "RECURSO_OCUPADO",
    title: titulo,
    message,
    userHint,
    conflictos,
  };
}

/** Error de negocio con estado HTTP (sin detalle). */
export function errorNegocio(status: number, message: string, reason?: string) {
  return { status, ok: false as const, message, ...(reason ? { reason, code: reason } : {}) };
}
