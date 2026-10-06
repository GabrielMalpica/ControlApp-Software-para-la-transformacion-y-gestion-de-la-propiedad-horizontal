// src/services/DefinicionTareaPreventivaService.ts

import type {
  PrismaClient,
  PreventivaExcluidaBorrador as PreventivaExcluidaBorradorRow,
} from "@prisma/client";
import { adjuntarCategoriaCronograma } from "../utils/categoriaCronograma";
import { randomUUID } from "node:crypto";
import {
  Prisma,
  TipoTarea,
  EstadoTarea,
  Frecuencia,
  DiaSemana,
  Rol,
  TipoFuncion,
} from "@prisma/client";
import { z } from "zod";

import {
  CrearDefinicionPreventivaDTO,
  EditarDefinicionPreventivaDTO,
  FiltroDefinicionPreventivaDTO,
  GenerarCronogramaDTO,
  ListarExcluidasBorradorDTO,
  SugerirHuecosExcluidaDTO,
  AgendarExcluidaDTO,
  ReemplazarConExcluidaDTO,
  EliminarPreventivasLoteDTO,
  PeriodoBorradorDTO,
  calcularMinutosEstimados,
} from "../model/DefinicionTareaPreventiva";

import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  OrigenAuditoria,
  type ActorAuditoria,
} from "../model/Auditoria";
import { AuditoriaService } from "./AuditoriaService";
import { CatalogoOperativoService } from "./CatalogoOperativoService";
import {
  ordenarCandidatasPorCarga,
  ordenarExcluidasParaRescate,
  motivoRescatablePorCapacidad,
  plazasCandidatas,
  type PlazaRecurso,
} from "../utils/capacidadCandidatos";
import {
  ordenarPorProgramacion,
  type DatosOrdenProgramacion,
} from "../utils/ordenProgramacion";
import { parseMaquinariaIdsComprometidos } from "../utils/maquinariaNecesidades";
import {
  DIAS_ENTREGA_RECOGIDA,
  calcularRangoReserva,
} from "../utils/reservaMaquinaria";

import type { Bloqueo, HorarioDia } from "../utils/agenda";
import {
  buildAgendaPorOperarioDia,
  buscarHuecoDiaConSplitEarliest,
  buscarHuecoDiaEarliest,
  freeFromOccupied,
  getFestivosSet,
  intentarReemplazoPorPrioridadBaja,
  isFestivoDate,
  mergeIntervalos,
  splitMinutes,
  toDateAtMin,
  toMinOfDay,
  toMinOfDaySafe,
  toMin,
  ymdLocal,
} from "../utils/schedulerUtils";

import {
  buildMaquinariaNoDisponibleError,
  type ConflictoMaquinaria,
} from "../utils/errorFormat";
import {
  construirRutaElemento,
  elementoParentChainInclude,
  operarioResumenSelect,
  supervisorResumenSelect,
} from "../utils/elementoHierarchy";
import {
  allowedIntervalsForUserWithAvailability,
  diaSemanaFromDate,
  obtenerIntervalosEfectivosProgramacion,
  obtenerHorariosEfectivosOperarios,
  validarIntervaloProgramacion,
  validarLimiteSemanalOperarios,
  obtenerDisponibilidadActivaOperarios,
  validarOperariosDisponiblesEnFecha,
  operariosPuedenTrabajarFestivo,
  obtenerConfigFestivoNecesidades,
  obtenerCalendariosOperarios,
} from "../utils/operarioAvailability";

/* =========================================================
 * Tipos auxiliares (patrones y jornada)
 * ======================================================= */

type Patron =
  | "MEDIO_DIAS_INTERCALADOS"
  | "MEDIO_SEMANA_SABADO"
  | "MEDIO_SEMANA_SABADO_TARDE";

type Jornada = "COMPLETA" | "MEDIO_TIEMPO";
type BloqueProgramacion = { fechaInicio: Date; fechaFin: Date };
type IntervaloAgendaScheduler = Intervalo & {
  tareaId: number;
  borrador: boolean;
};
type EstadoBloqueExcluida = "PENDIENTE" | "AGENDADO";
type BloqueExcluidaManual = {
  id: string;
  orden: number;
  duracionMinutos: number;
  estado: EstadoBloqueExcluida;
  tareaProgramadaId?: number | null;
  fechaInicio?: string | null;
  fechaFin?: string | null;
};
type DivisionManualExcluida = {
  activa: boolean;
  bloques: BloqueExcluidaManual[];
  actualizadaEn: string;
};

type NovedadCronograma =
  | {
      tipo: "FESTIVO_MOVIDO";
      defId: number;
      descripcion: string;
      prioridad: number;
      fechaOriginal: string;
      fechaNueva: string;
      mensaje?: string;
    }
  | {
      tipo: "REEMPLAZO_PRIORIDAD";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      nuevaTareaIds: number[];
      reprogramadasIds: number[];
      mensaje?: string;
    }
  | {
      tipo: "REQUIERE_CONFIRMACION_REEMPLAZO";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      prioridadObjetivo: number;
      candidatasIds: number[];
      mensaje: string;
    }
  | {
      tipo: "SIN_CANDIDATAS";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      mensaje?: string;
    }
  | {
      tipo: "SIN_HUECO";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      mensaje?: string;
    }
  | {
      tipo: "FESTIVO_OMITIDO";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      motivo: "FESTIVO" | "DOMINGO" | "DESCANSO_COMPENSATORIO";
      mensaje?: string;
    }
  | {
      tipo: "REUBICADA_EN_PERIODO";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      fechaObjetivo: string;
      nuevaTareaIds: number[];
      bloques: { fechaInicio: string; fechaFin: string }[];
      mensaje: string;
    }
  | {
      // El responsable previsto no tenia espacio y otra plaza con la categoria
      // habilitada en su perfil ejecuto la tarea (ver rescatarExcluidasPorCapacidad).
      tipo: "REASIGNADA_POR_CAPACIDAD";
      defId: number;
      descripcion: string;
      prioridad: number;
      fecha: string;
      fechaObjetivo: string;
      nuevaTareaIds: number[];
      desdeNecesidadId: number | null;
      haciaNecesidadId: number;
      haciaEtiqueta: string;
      haciaOperarioId: string;
      mensaje: string;
    };

type ExclusionMotivoTipo =
  | "SIN_CAPACIDAD_P1"
  | "SIN_CANDIDATAS"
  | "SIN_HUECO"
  | "REQUIERE_CONFIRMACION_REEMPLAZO"
  | "FESTIVO_OMITIDO"
  | "DESCANSO_COMPENSATORIO"
  | "REEMPLAZO_PRIORIDAD"
  | "MANUAL_REEMPLAZADA"
  | "MANUAL_ELIMINADA"
  | "REORDEN_MANUAL_SIN_HUECO"
  // La definición requiere una necesidad/plaza (ConjuntoNecesidadOperario)
  // que actualmente no tiene operario asignado: no se agenda a medias.
  | "NECESIDAD_SIN_OPERARIO";

/**
 * Identidad "de negocio" de una tarea para la regla de no repetir el mismo
 * día: descripción + ubicación + elemento. Dos definiciones distintas con la
 * misma firma son, para el usuario, la misma tarea (p. ej. un barrido cargado
 * tres veces con distinto id de definición).
 */
function firmaTareaPreventiva(params: {
  descripcion?: string | null;
  ubicacionId?: number | null;
  elementoId?: number | null;
}): string | null {
  if (
    !params.descripcion ||
    params.ubicacionId == null ||
    params.elementoId == null
  ) {
    return null;
  }
  const descripcion = params.descripcion.trim().toLowerCase().replace(/\s+/g, " ");
  return `${descripcion}|${params.ubicacionId}|${params.elementoId}`;
}

type IdentidadTareaDia = {
  definicionId?: number | null;
  descripcion?: string | null;
  ubicacionId?: number | null;
  elementoId?: number | null;
  ocurrenciaPlanId?: string | null;
  grupoPlanId?: string | null;
};

type ExcluidaSnapshot = {
  conjuntoId: string;
  periodoAnio: number;
  periodoMes: number;
  defId?: number | null;
  origenTareaId?: number | null;
  tareaProgramadaId?: number | null;
  ocurrenciaPlanId?: string | null;
  descripcion: string;
  frecuencia?: Frecuencia | null;
  diaSemanaProgramado?: DiaSemana | null;
  prioridad: number;
  duracionMinutos: number;
  fechaObjetivo: Date;
  ubicacionId: number;
  ubicacionNombre?: string | null;
  elementoId: number;
  elementoNombre?: string | null;
  supervisorId?: string | null;
  supervisorNombre?: string | null;
  operariosIds?: string[];
  operariosNombres?: string[];
  motivoTipo: ExclusionMotivoTipo;
  motivoMensaje?: string | null;
  metadataJson?: Prisma.InputJsonValue;
};

const dayKey = (d: Date) => ymdLocal(d);

/**
 * Horario efectivo de un día para el generador/rescate: si `dia` es festivo
 * (según el set SIN filtrar, `festivosSetRaw`), usa el horario festivo de la
 * plaza (`festivoHorario`, ya resuelto para el conjunto de operarios de la
 * definición); si no, el horario normal por día de semana. En un festivo
 * que la definición no puede trabajar, `festivoHorario` es `null` -y ese día
 * ya debería haber quedado filtrado antes de llegar aquí por el gate
 * `festivosSetDef.has(dayKey(dia))` que sigue existiendo sin cambios-.
 */
function resolverHorarioConFestivo(
  dia: Date,
  horariosPorDia: Map<DiaSemana, HorarioDia>,
  festivosSetRaw: Set<string>,
  festivoHorario: HorarioDia | null | undefined,
): HorarioDia | undefined {
  if (festivosSetRaw.has(dayKey(dia))) {
    return festivoHorario ?? undefined;
  }
  return horariosPorDia.get(dateToDiaSemana(dia));
}

/**
 * Tope de bloques en que la fase de rescate puede partir una tarea dentro de un mismo dia.
 * Con 3 se cubre el caso tipico "mañana + antes del almuerzo + tarde" sin fragmentar en exceso.
 */
const MAX_BLOQUES_RESCATE_POR_DIA = 2;

/**
 * Clave de respaldo para emparejar una definicion con sus tareas de borrador
 * cuando la fila es anterior a `Tarea.definicionId` y no lo tiene relleno.
 */
function claveDefinicionBorrador(def: {
  descripcion: string;
  ubicacionId: number;
  elementoId: number;
  frecuencia: Frecuencia | null;
}): string {
  return [
    def.descripcion.trim(),
    def.ubicacionId,
    def.elementoId,
    def.frecuencia ?? "",
  ].join("|");
}

type VersionDefinicionBorrador = {
  id: number;
  actualizadoEn: string;
};

function versionesDefinicionesDesdeMetadata(
  metadata: unknown,
): Map<number, string> {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    return new Map();
  }

  const raw = (metadata as Record<string, unknown>).versionesDefiniciones;
  if (!Array.isArray(raw)) return new Map();

  const versiones = new Map<number, string>();
  for (const item of raw) {
    if (!item || typeof item !== "object" || Array.isArray(item)) continue;
    const id = Number((item as Record<string, unknown>).id);
    const actualizadoEn = String(
      (item as Record<string, unknown>).actualizadoEn ?? "",
    );
    if (Number.isInteger(id) && id > 0 && actualizadoEn) {
      versiones.set(id, actualizadoEn);
    }
  }
  return versiones;
}

/**
 * Preventivas que, al generar el borrador, no produjeron ninguna tarea,
 * excluida ni ocurrencia en el periodo (p. ej. una semestral cuyas fechas caen
 * en otros meses). No son "pendientes": regenerar no las va a planificar.
 */
function definicionesSinOcurrenciaDesdeMetadata(metadata: unknown): Set<number> {
  if (!metadata || typeof metadata !== "object" || Array.isArray(metadata)) {
    return new Set();
  }
  const raw = (metadata as Record<string, unknown>).definicionesSinOcurrencia;
  if (!Array.isArray(raw)) return new Set();
  return new Set(
    raw.map((id) => Number(id)).filter((id) => Number.isInteger(id) && id > 0),
  );
}

function versionActualDefinicion(def: {
  actualizadoEn?: Date | null;
  creadoEn?: Date | null;
}): string {
  return (def.actualizadoEn ?? def.creadoEn ?? new Date(0)).toISOString();
}

/** Minutos totales cubiertos por un plan de bloques. */
function duracionDeBloques(bloques: BloqueProgramacion[]): number {
  return bloques.reduce(
    (total, bloque) =>
      total +
      Math.max(1, Math.round((bloque.fechaFin.getTime() - bloque.fechaInicio.getTime()) / 60000)),
    0,
  );
}

/* =========================================================
 * DTOs internos (Zod)
 * ======================================================= */

const DividirTareaBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  bloques: z
    .array(
      z.object({
        fechaInicio: z.coerce.date(),
        fechaFin: z.coerce.date(),
      }),
    )
    .min(2, "Debe dividirse en al menos 2 bloques"),
});

const EditarBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionMinutos: z.number().int().min(1).optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
});

const CrearBloqueBorradorDTO = z.object({
  descripcion: z.string().min(3),
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
  ubicacionId: z.number().int().positive(),
  elementoId: z.number().int().positive(),
  operariosIds: z.array(z.number().int().positive()).optional(),
  supervisorId: z.number().int().positive().nullable().optional(),
  tiempoEstimadoMinutos: z.number().positive().optional(),
});

const DividirBloqueDTO = z.object({
  fechaInicio1: z.coerce.date(),
  fechaFin1: z.coerce.date(),
  fechaInicio2: z.coerce.date(),
  fechaFin2: z.coerce.date(),
});

const EditarBloqueBorradorDTO = z.object({
  descripcion: z.string().min(3).optional(),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
  duracionMinutos: z.number().int().positive().optional(),
  ubicacionId: z.number().int().positive().optional(),
  elementoId: z.number().int().positive().optional(),
  operariosIds: z.array(z.number().int().positive()).optional(),
  supervisorId: z.number().int().positive().nullable().optional(),
  tiempoEstimadoMinutos: z.number().positive().nullable().optional(),
});

const ReasignarOperarioBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  tareaId: z.number().int().positive(),
  nuevoOperarioId: z.coerce.number().int().positive(),
  modoAplicacion: z
    .enum(["SOLO_TAREA", "TODO_BORRADOR", "TAMBIEN_DEFINICION"])
    .optional(),
  aplicarADefinicion: z.boolean().optional().default(false),
});

const ReasignarOperarioExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.number().int().positive(),
  nuevoOperarioId: z.coerce.number().int().positive(),
  modoAplicacion: z
    .enum(["SOLO_TAREA", "TODO_BORRADOR", "TAMBIEN_DEFINICION"])
    .optional(),
  aplicarADefinicion: z.boolean().optional().default(false),
});

const tareaBorradorDetalleInclude = {
  operarios: { select: operarioResumenSelect },
  ubicacion: true,
  elemento: { include: elementoParentChainInclude },
  supervisor: { select: supervisorResumenSelect },
  // Distintivo visual: la tarea viene de una plaza con horario especial
  // (puede caer fuera del horario general del conjunto).
  necesidades: { select: { id: true, etiqueta: true, horarioEspecial: true } },
} satisfies Prisma.TareaInclude;

const DividirExcluidaManualDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.number().int().positive(),
  bloques: z
    .array(
      z.object({
        duracionMinutos: z.number().int().positive(),
      }),
    )
    .min(2, "Debes crear al menos 2 bloques"),
});

const GestionarBloqueExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.number().int().positive(),
  bloqueId: z.string().min(1),
  fechaInicio: z.coerce.date().optional(),
  fechaFin: z.coerce.date().optional(),
});

const ReordenarTareasDiaBorradorDTO = z.object({
  conjuntoId: z.string().min(3),
  fecha: z.coerce.date(),
  tareaIds: z.array(z.number().int().positive()).min(2),
  // Cuando la cascada de ajustes necesita excluir alguna tarea, la primera
  // llamada devuelve la vista previa (requiereConfirmacion:true) sin escribir
  // nada; el frontend vuelve a llamar con este flag en true para aplicarla.
  confirmarExclusiones: z.boolean().optional().default(false),
});

/* =========================================================
 * Service
 * ======================================================= */

export class DefinicionTareaPreventivaService {
  private auditoria: AuditoriaService;
  private disponibilidadSchedulerCache = new Map<
    string,
    { ok: boolean; noDisponibles: string[] }
  >();
  private bloqueosPatronSchedulerCache = new Map<string, Bloqueo[]>();
  private limiteSemanalSchedulerCache = new Map<string, number>();
  private minutosSemanaSchedulerCache = new Map<string, number>();
  // Necesidades operativas: horariosPorDia resuelto para un conjunto de
  // operarios concreto (la(s) plaza(s) de una definición, o el conjunto
  // completo cuando no hay necesidades). Clave: `${conjuntoId}|${idsOrdenados}`.
  private horariosPorOperariosCache = new Map<string, Map<DiaSemana, HorarioDia>>();
  // Horario festivo envolvente de un conjunto de operarios (null si alguno
  // no tiene plaza con trabajaFestivos). Misma clave que horariosPorOperariosCache.
  private festivoHorarioCache = new Map<string, HorarioDia | null>();
  // Días de descanso compensatorio (unión de todos los operarios) para un
  // conjunto de operarios en un periodo. Clave: `${conjuntoId}|${ids}|${anio}-${mes}`.
  private diasDescansoCache = new Map<string, Set<string>>();
  private agendaSchedulerActiva = false;
  /** Excluidas creadas durante la generacion en curso (candidatas al rescate por capacidades). */
  private excluidasDeLaCorrida: PreventivaExcluidaBorradorRow[] = [];
  private rastreoExcluidas = false;
  private agendaScheduler = new Map<string, IntervaloAgendaScheduler[]>();
  private ocurrenciasDefinicionDiaScheduler = new Map<string, Set<string>>();
  /** definicionId -> firma (descripción|ubicación|elemento) de la generación en curso. */
  private firmaPorDefinicionScheduler = new Map<number, string>();
  private ocurrenciaPlanRunId = randomUUID();

  constructor(
    private prisma: PrismaClient,
    private actor?: ActorAuditoria,
  ) {
    this.auditoria = new AuditoriaService(prisma);
  }

  private claveOperariosDia(fecha: Date, operariosIds: string[]) {
    return `${dayKey(fecha)}|${[...operariosIds].sort().join(",")}`;
  }

  /**
   * Necesidad primero, operario como respaldo: si la definición tiene
   * plazas (necesidades) vinculadas, el operario a agendar es el que
   * ocupa cada plaza (puede haber plazas vacantes -> se filtran, y el
   * llamador decide qué hacer si el resultado queda incompleto). Si no
   * tiene ninguna, se conserva el camino directo `operarios` de siempre.
   */
  /**
   * Resuelve los ids de necesidades (plazas) vinculadas a una definición,
   * para conectarlos en una tarea creada manualmente a partir de ella
   * (split, reprogramación desde excluidas, bloque manual, reordenamiento).
   * Sin esto, esas tareas pierden el distintivo visual de horario especial
   * aunque sigan siendo de la misma plaza -solo `crearBloquesPreventivosDeDefinicion`
   * (el generador automático) lo conectaba-. `[]` si la definición no usa
   * necesidades o no existe (p.ej. bloque 100% manual sin definicionId).
   */
  private async necesidadesIdsDeDefId(
    defId: number | null | undefined,
    client: PrismaClient | Prisma.TransactionClient = this.prisma,
  ): Promise<number[]> {
    if (defId == null) return [];
    const def = await client.definicionTareaPreventiva.findUnique({
      where: { id: defId },
      select: { necesidades: { select: { id: true } } },
    });
    return def?.necesidades.map((n) => n.id) ?? [];
  }

  private operariosIdsDeDefinicion(def: {
    operarios: Array<{ id: string }>;
    necesidades?: Array<{ operarioId: string | null }>;
  }): { operariosIds: string[]; necesidadesVacantes: boolean } {
    if (!def.necesidades?.length) {
      return { operariosIds: def.operarios.map((o) => o.id), necesidadesVacantes: false };
    }
    const operariosIds = def.necesidades
      .map((n) => n.operarioId)
      .filter((id): id is string => !!id);
    return {
      operariosIds,
      necesidadesVacantes: operariosIds.length < def.necesidades.length,
    };
  }

  /**
   * Igual que operariosIdsDeDefinicion pero para snapshots de excluidas
   * (necesita también los nombres). Una plaza vacante simplemente no
   * aporta id/nombre: no hay nadie que mostrar en esa posición.
   */
  private operariosSnapshotDeDefinicion(def: {
    operarios: Array<{ id: string; usuario?: { nombre?: string | null } | null }>;
    necesidades?: Array<{
      operarioId: string | null;
      operario?: { id: string; usuario?: { nombre?: string | null } | null } | null;
    }>;
  }): { ids: string[]; nombres: string[] } {
    if (!def.necesidades?.length) {
      return {
        ids: def.operarios.map((o) => o.id),
        nombres: def.operarios
          .map((o) => o.usuario?.nombre ?? "")
          .filter((name) => name.trim().length > 0),
      };
    }
    const ocupadas = def.necesidades.filter((n) => n.operarioId && n.operario);
    return {
      ids: ocupadas.map((n) => n.operarioId as string),
      nombres: ocupadas
        .map((n) => n.operario?.usuario?.nombre ?? "")
        .filter((name) => name.trim().length > 0),
    };
  }

  /**
   * Horario base para buscar hueco, resuelto para un conjunto concreto de
   * operarios (típicamente los que ocupan la(s) plaza(s) de una
   * definición). Es la ventana ENVOLVENTE (mínimo inicio, máximo cierre)
   * de la ventana efectiva de cada operario ese día -la misma composición
   * que ya usa el resto del algoritmo: horario amplio + bloqueosPatron
   * (derivados de la intersección real) recortan el resto-. Sin
   * operariosIds, es el horario general del conjunto de siempre.
   */
  private async horariosPorDiaParaOperarios(
    conjuntoId: string,
    operariosIds: string[],
  ): Promise<Map<DiaSemana, HorarioDia>> {
    const idsUnicos = Array.from(new Set(operariosIds));
    const clave = `${conjuntoId}|${idsUnicos.slice().sort().join(",")}`;
    const cacheada = this.horariosPorOperariosCache.get(clave);
    if (cacheada) return cacheada;

    const mapa = new Map<DiaSemana, HorarioDia>();

    if (!idsUnicos.length) {
      // Sin operarios ni necesidades: comportamiento actual intacto.
      const horarios = await this.prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
      for (const h of horarios) {
        mapa.set(h.dia, {
          startMin: toMin(h.horaApertura),
          endMin: toMin(h.horaCierre),
          descansoStartMin: h.descansoInicio ? toMin(h.descansoInicio) : undefined,
          descansoEndMin: h.descansoFin ? toMin(h.descansoFin) : undefined,
        });
      }
      this.horariosPorOperariosCache.set(clave, mapa);
      return mapa;
    }

    for (const dia of Object.values(DiaSemana)) {
      const horariosEfectivos = await obtenerHorariosEfectivosOperarios({
        prisma: this.prisma,
        conjuntoId,
        operariosIds: idsUnicos,
        dia,
      });

      let startMin: number | null = null;
      let endMin: number | null = null;
      const descansos: Array<{ i: number; f: number }> = [];
      for (const id of idsUnicos) {
        const h = horariosEfectivos.get(id);
        if (!h) continue;
        startMin = startMin == null ? h.startMin : Math.min(startMin, h.startMin);
        endMin = endMin == null ? h.endMin : Math.max(endMin, h.endMin);
        if (h.descansoStartMin != null && h.descansoEndMin != null) {
          descansos.push({ i: h.descansoStartMin, f: h.descansoEndMin });
        }
      }
      // Ningún operario tiene ventana ese día (p.ej. su plaza no lo cubre) -> sin fila.
      if (startMin == null || endMin == null) continue;

      // El descanso de la envolvente solo se conserva si TODOS los
      // operarios con ventana ese día comparten exactamente el mismo
      // horario de descanso; si difieren se omite aquí (los bloqueos por
      // patrón/disponibilidad, derivados de la intersección real, se
      // encargan del recorte fino de cada operario).
      let descansoStartMin: number | undefined;
      let descansoEndMin: number | undefined;
      if (
        descansos.length > 0 &&
        descansos.every((d) => d.i === descansos[0].i && d.f === descansos[0].f)
      ) {
        descansoStartMin = descansos[0].i;
        descansoEndMin = descansos[0].f;
      }

      mapa.set(dia, { startMin, endMin, descansoStartMin, descansoEndMin });
    }

    this.horariosPorOperariosCache.set(clave, mapa);
    return mapa;
  }

  /**
   * Horario festivo envolvente (mínimo inicio, máximo cierre) de las plazas
   * de estos operarios -análogo a horariosPorDiaParaOperarios, pero para el
   * horario festivo (no depende del día de semana)-. `null` si no hay
   * operarios, o si alguno no ocupa una plaza con `trabajaFestivos` (ver
   * operariosPuedenTrabajarFestivo: para que la definición trabaje festivos,
   * TODOS sus operarios/necesidades deben poder hacerlo).
   */
  private async festivoHorarioParaOperarios(
    conjuntoId: string,
    operariosIds: string[],
  ): Promise<HorarioDia | null> {
    const idsUnicos = Array.from(new Set(operariosIds)).sort();
    if (!idsUnicos.length) return null;
    const clave = `${conjuntoId}|${idsUnicos.join(",")}`;
    const cacheado = this.festivoHorarioCache.get(clave);
    if (cacheado !== undefined) return cacheado;

    const puedenTrabajar = await operariosPuedenTrabajarFestivo({
      prisma: this.prisma,
      conjuntoId,
      operariosIds: idsUnicos,
    });
    if (!puedenTrabajar) {
      this.festivoHorarioCache.set(clave, null);
      return null;
    }

    const configs = await obtenerConfigFestivoNecesidades({
      prisma: this.prisma,
      conjuntoId,
      operariosIds: idsUnicos,
    });

    let startMin: number | null = null;
    let endMin: number | null = null;
    const descansos: Array<{ i: number; f: number }> = [];
    for (const id of idsUnicos) {
      const config = configs.get(id);
      if (!config?.festivoHoraApertura || !config.festivoHoraCierre) continue;
      const s = toMin(config.festivoHoraApertura);
      const e = toMin(config.festivoHoraCierre);
      if (e <= s) continue;
      startMin = startMin == null ? s : Math.min(startMin, s);
      endMin = endMin == null ? e : Math.max(endMin, e);
      if (config.festivoDescansoInicio && config.festivoDescansoFin) {
        descansos.push({ i: toMin(config.festivoDescansoInicio), f: toMin(config.festivoDescansoFin) });
      }
    }
    if (startMin == null || endMin == null) {
      this.festivoHorarioCache.set(clave, null);
      return null;
    }

    let descansoStartMin: number | undefined;
    let descansoEndMin: number | undefined;
    if (
      descansos.length > 0 &&
      descansos.every((d) => d.i === descansos[0].i && d.f === descansos[0].f)
    ) {
      descansoStartMin = descansos[0].i;
      descansoEndMin = descansos[0].f;
    }

    const resultado: HorarioDia = { startMin, endMin, descansoStartMin, descansoEndMin };
    this.festivoHorarioCache.set(clave, resultado);
    return resultado;
  }

  /**
   * Días (ymd) dentro de [inicio, fin] en que ALGUNO de estos operarios
   * tiene descanso compensatorio por su plaza -si cualquiera descansa, el
   * grupo completo no puede agendarse ese día-. Vacío si ninguno tiene
   * `descansoCompensatorio` activo (comportamiento previo intacto).
   */
  private async diasDescansoParaOperarios(
    conjuntoId: string,
    operariosIds: string[],
    inicio: Date,
    fin: Date,
  ): Promise<Set<string>> {
    const idsUnicos = Array.from(new Set(operariosIds)).sort();
    if (!idsUnicos.length) return new Set();
    const clave = `${conjuntoId}|${idsUnicos.join(",")}|${dayKey(inicio)}-${dayKey(fin)}`;
    const cacheado = this.diasDescansoCache.get(clave);
    if (cacheado) return cacheado;

    const calendarios = await obtenerCalendariosOperarios({
      prisma: this.prisma,
      conjuntoId,
      operariosIds: idsUnicos,
      desde: inicio,
      hasta: fin,
    });
    const dias = new Set<string>();
    for (const calendario of calendarios.values()) {
      for (const [ymd, info] of calendario) {
        if (info.tipo === "DESCANSO") dias.add(ymd);
      }
    }
    this.diasDescansoCache.set(clave, dias);
    return dias;
  }

  private async disponibilidadScheduler(params: {
    fecha: Date;
    operariosIds: string[];
  }): Promise<{ ok: boolean; noDisponibles: string[] }> {
    if (!params.operariosIds.length) return { ok: true, noDisponibles: [] };
    const clave = this.claveOperariosDia(params.fecha, params.operariosIds);
    const existente = this.disponibilidadSchedulerCache.get(clave);
    if (existente) return existente;
    const disponibilidad = await validarOperariosDisponiblesEnFecha({
      prisma: this.prisma,
      fecha: params.fecha,
      operariosIds: params.operariosIds,
    });
    this.disponibilidadSchedulerCache.set(clave, disponibilidad);
    return disponibilidad;
  }

  private async bloqueosPatronScheduler(params: {
    conjuntoId: string;
    fecha: Date;
    horario: HorarioDia;
    operariosIds: string[];
  }): Promise<Bloqueo[]> {
    if (!params.operariosIds.length) return [];
    const clave = `${params.conjuntoId}|${this.claveOperariosDia(params.fecha, params.operariosIds)}`;
    const existentes = this.bloqueosPatronSchedulerCache.get(clave);
    if (existentes) return existentes;
    const bloqueos = await buildBloqueosPorPatronJornada({
      prisma: this.prisma,
      conjuntoId: params.conjuntoId,
      fechaDia: params.fecha,
      horarioDia: params.horario,
      operariosIds: params.operariosIds,
    });
    this.bloqueosPatronSchedulerCache.set(clave, bloqueos);
    return bloqueos;
  }

  private registrarBloquesEnCacheSemanal(
    bloques: BloqueProgramacion[],
    operariosIds: string[],
  ) {
    for (const bloque of bloques) {
      const semana = dayKey(inicioSemana(bloque.fechaInicio));
      const minutos = Math.max(
        1,
        Math.round((+bloque.fechaFin - +bloque.fechaInicio) / 60_000),
      );
      for (const operarioId of operariosIds) {
        for (const incluirPublicadas of [true, false]) {
          const clave = `${operarioId}|${semana}|${incluirPublicadas}`;
          const actuales = this.minutosSemanaSchedulerCache.get(clave);
          if (actuales != null) {
            this.minutosSemanaSchedulerCache.set(clave, actuales + minutos);
          }
        }
      }
    }
  }

  private claveAgendaScheduler(operarioId: string, fecha: Date) {
    return `${operarioId}|${dayKey(fecha)}`;
  }

  private claveDefinicionDiaScheduler(definicionId: number, fecha: Date) {
    return `${definicionId}|${dayKey(fecha)}`;
  }

  private registrarOcurrenciaDefinicionDiaScheduler(params: {
    definicionId: number;
    ocurrenciaPlanId: string;
    bloques: BloqueProgramacion[];
    firma?: string | null;
  }) {
    const firma =
      params.firma ?? this.firmaPorDefinicionScheduler.get(params.definicionId);
    for (const bloque of params.bloques) {
      const claves = [
        this.claveDefinicionDiaScheduler(params.definicionId, bloque.fechaInicio),
        ...(firma ? [`F|${firma}|${dayKey(bloque.fechaInicio)}`] : []),
      ];
      for (const clave of claves) {
        const ocurrencias =
          this.ocurrenciasDefinicionDiaScheduler.get(clave) ?? new Set<string>();
        ocurrencias.add(params.ocurrenciaPlanId);
        this.ocurrenciasDefinicionDiaScheduler.set(clave, ocurrencias);
      }
    }
  }

  /** Registra una tarea que no pertenece a una definición (solo por su firma). */
  private registrarOcurrenciaFirmaDiaScheduler(params: {
    firma: string;
    ocurrenciaPlanId: string;
    fecha: Date;
  }) {
    const clave = `F|${params.firma}|${dayKey(params.fecha)}`;
    const ocurrencias =
      this.ocurrenciasDefinicionDiaScheduler.get(clave) ?? new Set<string>();
    ocurrencias.add(params.ocurrenciaPlanId);
    this.ocurrenciasDefinicionDiaScheduler.set(clave, ocurrencias);
  }

  private hayOtraOcurrenciaDefinicionEnDia(params: {
    definicionId: number;
    ocurrenciaPlanId: string;
    fecha: Date;
  }) {
    const firma = this.firmaPorDefinicionScheduler.get(params.definicionId);
    const claves = [
      this.claveDefinicionDiaScheduler(params.definicionId, params.fecha),
      ...(firma ? [`F|${firma}|${dayKey(params.fecha)}`] : []),
    ];
    return claves.some((clave) => {
      const ocurrencias = this.ocurrenciasDefinicionDiaScheduler.get(clave);
      return (
        ocurrencias != null &&
        Array.from(ocurrencias).some(
          (ocurrenciaId) => ocurrenciaId !== params.ocurrenciaPlanId,
        )
      );
    });
  }

  /**
   * Conserva el orden funcional recibido (proximidad, carga, etc.) mismo,
   * pero descarta por completo los dias que ya contienen otra ocurrencia de
   * la misma definicion: un operario no debe repetir la misma tarea dos
   * veces el mismo dia. Si ningun dia del mes queda libre, se devuelve una
   * lista vacia y la ocurrencia queda excluida en vez de duplicarse.
   */
  private priorizarDiasSinRepetirDefinicion(params: {
    dias: Date[];
    definicionId: number;
    ocurrenciaPlanId: string;
  }) {
    return params.dias.filter(
      (dia) =>
        !this.hayOtraOcurrenciaDefinicionEnDia({
          definicionId: params.definicionId,
          ocurrenciaPlanId: params.ocurrenciaPlanId,
          fecha: dia,
        }),
    );
  }

  private async iniciarAgendaScheduler(params: {
    conjuntoId: string;
    inicio: Date;
    fin: Date;
  }) {
    this.agendaScheduler.clear();
    this.ocurrenciasDefinicionDiaScheduler.clear();
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: params.conjuntoId,
        fechaInicio: { lte: params.fin },
        fechaFin: { gte: params.inicio },
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
      },
      select: {
        id: true,
        fechaInicio: true,
        fechaFin: true,
        ocurrenciaPlanId: true,
        grupoPlanId: true,
        definicionId: true,
        descripcion: true,
        ubicacionId: true,
        elementoId: true,
        borrador: true,
        operarios: { select: { id: true } },
      },
    });
    this.agendaSchedulerActiva = true;
    for (const tarea of tareas) {
      this.registrarIntervaloAgendaScheduler({
        tareaId: tarea.id,
        fechaInicio: tarea.fechaInicio,
        fechaFin: tarea.fechaFin,
        operariosIds: tarea.operarios.map((operario) => operario.id),
        borrador: tarea.borrador,
      });
      // Una tarea sin ocurrenciaPlanId (creada a mano o heredada) también
      // cuenta como ocurrencia de su definición ese día; antes se ignoraba y
      // el generador podía repetir la tarea.
      const ocurrenciaTarea =
        tarea.ocurrenciaPlanId ?? tarea.grupoPlanId ?? `tarea:${tarea.id}`;
      const firmaTarea = firmaTareaPreventiva(tarea);
      if (tarea.definicionId != null) {
        this.registrarOcurrenciaDefinicionDiaScheduler({
          definicionId: tarea.definicionId,
          ocurrenciaPlanId: ocurrenciaTarea,
          bloques: [
            { fechaInicio: tarea.fechaInicio, fechaFin: tarea.fechaFin },
          ],
          firma: firmaTarea,
        });
      } else if (firmaTarea) {
        this.registrarOcurrenciaFirmaDiaScheduler({
          firma: firmaTarea,
          ocurrenciaPlanId: ocurrenciaTarea,
          fecha: tarea.fechaInicio,
        });
      }
    }
  }

  private registrarIntervaloAgendaScheduler(params: {
    tareaId: number;
    fechaInicio: Date;
    fechaFin: Date;
    operariosIds: string[];
    borrador: boolean;
  }) {
    if (!this.agendaSchedulerActiva) return;
    const intervalo: IntervaloAgendaScheduler = {
      i: toMinOfDay(params.fechaInicio),
      f: toMinOfDay(params.fechaFin),
      tareaId: params.tareaId,
      borrador: params.borrador,
    };
    for (const operarioId of params.operariosIds) {
      const clave = this.claveAgendaScheduler(operarioId, params.fechaInicio);
      const intervalos = this.agendaScheduler.get(clave) ?? [];
      intervalos.push(intervalo);
      this.agendaScheduler.set(clave, intervalos);
    }
  }

  private retirarTareasAgendaScheduler(tareaIds: number[]) {
    if (!this.agendaSchedulerActiva || !tareaIds.length) return;
    const ids = new Set(tareaIds);
    for (const [clave, intervalos] of this.agendaScheduler) {
      const restantes = intervalos.filter(
        (intervalo) => !ids.has(intervalo.tareaId),
      );
      if (restantes.length) this.agendaScheduler.set(clave, restantes);
      else this.agendaScheduler.delete(clave);
    }
  }

  private ocupadosAgendaScheduler(params: {
    fecha: Date;
    operariosIds: string[];
    incluirPublicadas: boolean;
    bloqueos: Bloqueo[];
  }): Intervalo[] {
    const intervalos: Intervalo[] = [];
    for (const operarioId of params.operariosIds) {
      const clave = this.claveAgendaScheduler(operarioId, params.fecha);
      for (const intervalo of this.agendaScheduler.get(clave) ?? []) {
        if (!params.incluirPublicadas && !intervalo.borrador) continue;
        intervalos.push({ i: intervalo.i, f: intervalo.f });
      }
    }
    intervalos.push(
      ...params.bloqueos.map((bloqueo) => ({
        i: bloqueo.startMin,
        f: bloqueo.endMin,
      })),
    );
    return mergeIntervalos(intervalos);
  }

  private async limpiarExcluidasDeMesesAnteriores(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;
    await this.prisma.preventivaExcluidaBorrador.deleteMany({
      where: {
        conjuntoId,
        OR: [
          { periodoAnio: { lt: anio } },
          { periodoAnio: anio, periodoMes: { lt: mes } },
        ],
      },
    });
  }

  /**
   * Definiciones que ya tienen presencia en el borrador del periodo, ya sea como
   * tarea programada o como excluida. Se devuelven por id y por clave de respaldo,
   * porque las filas creadas antes de `Tarea.definicionId` no lo tienen relleno.
   */
  private async definicionesConBorrador(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
  }): Promise<{ defIds: Set<number>; claves: Set<string> }> {
    const { conjuntoId, periodoAnio, periodoMes } = params;

    const ocurrenciasRepo = (this.prisma as any).preventivaOcurrenciaPlan;
    const [tareas, excluidas, ocurrencias] = await Promise.all([
      this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          borrador: true,
          periodoAnio,
          periodoMes,
          tipo: TipoTarea.PREVENTIVA,
        },
        select: {
          definicionId: true,
          descripcion: true,
          ubicacionId: true,
          elementoId: true,
          frecuencia: true,
        },
      }),
      this.prisma.preventivaExcluidaBorrador.findMany({
        where: { conjuntoId, periodoAnio, periodoMes },
        select: {
          defId: true,
          descripcion: true,
          ubicacionId: true,
          elementoId: true,
          frecuencia: true,
        },
      }),
      ocurrenciasRepo?.findMany
        ? ocurrenciasRepo.findMany({
            where: { conjuntoId, periodoAnio, periodoMes, borrador: true },
            select: {
              defId: true,
              descripcion: true,
              ubicacionId: true,
              elementoId: true,
              frecuencia: true,
            },
          })
        : Promise.resolve([]),
    ]);

    const defIds = new Set<number>();
    const claves = new Set<string>();

    for (const tarea of tareas) {
      if (tarea.definicionId != null) defIds.add(tarea.definicionId);
      claves.add(claveDefinicionBorrador(tarea));
    }
    for (const excluida of excluidas) {
      if (excluida.defId != null) defIds.add(excluida.defId);
      claves.add(claveDefinicionBorrador(excluida));
    }
    for (const ocurrencia of ocurrencias as any[]) {
      if (ocurrencia.defId != null) defIds.add(ocurrencia.defId);
      claves.add(claveDefinicionBorrador(ocurrencia));
    }

    return { defIds, claves };
  }

  /**
   * Resumen del borrador guardado de un periodo: permite decidir si hay que
   * generarlo por primera vez y avisar de cuantas preventivas quedan sin planificar.
   */
  async estadoBorrador(payload: unknown) {
    const dto = PeriodoBorradorDTO.parse(payload);
    const { conjuntoId, anio, mes } = dto;

    const ocurrenciasRepo = (this.prisma as any).preventivaOcurrenciaPlan;
    const [
      totalTareas,
      excluidasPendientes,
      definiciones,
      totalOcurrencias,
      marcaGeneracion,
    ] =
      await Promise.all([
        this.prisma.tarea.count({
          where: {
            conjuntoId,
            borrador: true,
            periodoAnio: anio,
            periodoMes: mes,
            tipo: TipoTarea.PREVENTIVA,
          },
        }),
        this.prisma.preventivaExcluidaBorrador.count({
          where: {
            conjuntoId,
            periodoAnio: anio,
            periodoMes: mes,
            estado: "PENDIENTE",
          },
        }),
        this.prisma.definicionTareaPreventiva.findMany({
          where: { conjuntoId, activo: true },
          select: {
            id: true,
            descripcion: true,
            ubicacionId: true,
            elementoId: true,
            frecuencia: true,
            creadoEn: true,
            actualizadoEn: true,
          },
        }),
        ocurrenciasRepo?.count
          ? ocurrenciasRepo.count({
              where: {
                conjuntoId,
                periodoAnio: anio,
                periodoMes: mes,
                borrador: true,
              },
            })
          : Promise.resolve(0),
        this.prisma.preventivaBorradorEvento.findFirst({
          where: {
            conjuntoId,
            periodoAnio: anio,
            periodoMes: mes,
            tipo: "BORRADOR_GENERADO",
          },
          orderBy: { creadoEn: "desc" },
          select: { creadoEn: true, metadataJson: true },
        }),
      ]);

    const enBorrador = await this.definicionesConBorrador({
      conjuntoId,
      periodoAnio: anio,
      periodoMes: mes,
    });

    // Las que el generador ya evaluó y no tocaban este periodo no cuentan como
    // pendientes: antes quedaban como "nueva(s)" para siempre.
    const sinOcurrenciaEnPeriodo = definicionesSinOcurrenciaDesdeMetadata(
      marcaGeneracion?.metadataJson,
    );
    const sinPlanificar = definiciones.filter(
      (def) =>
        !enBorrador.defIds.has(def.id) &&
        !enBorrador.claves.has(claveDefinicionBorrador(def)) &&
        !sinOcurrenciaEnPeriodo.has(def.id),
    );

    const versionesGuardadas = versionesDefinicionesDesdeMetadata(
      marcaGeneracion?.metadataJson,
    );
    const idsSinPlanificar = new Set(sinPlanificar.map((def) => def.id));
    const definicionesModificadas = definiciones.filter((def) => {
      if (idsSinPlanificar.has(def.id)) return false;
      const versionGuardada = versionesGuardadas.get(def.id);
      if (versionGuardada) {
        return versionGuardada !== versionActualDefinicion(def);
      }
      return Boolean(
        marcaGeneracion &&
          def.actualizadoEn &&
          def.actualizadoEn.getTime() > marcaGeneracion.creadoEn.getTime(),
      );
    });
    const idsActivos = new Set(definiciones.map((def) => def.id));
    const definicionesRetiradas = Array.from(versionesGuardadas.keys()).filter(
      (id) => !idsActivos.has(id),
    );
    const existeFisicamente =
      totalTareas > 0 || excluidasPendientes > 0 || totalOcurrencias > 0;
    const cacheGestionado = marcaGeneracion != null;
    const desactualizado =
      sinPlanificar.length > 0 ||
      definicionesModificadas.length > 0 ||
      definicionesRetiradas.length > 0;

    return {
      // Filas antiguas con borrador=true no se ofrecen como caché si nunca
      // fueron marcadas por el flujo de borrador persistente.
      existe: existeFisicamente && cacheGestionado,
      cacheGestionado,
      borradorAnteriorSinMarca: existeFisicamente && !cacheGestionado,
      desactualizado,
      anio,
      mes,
      totalTareas,
      totalOcurrencias,
      excluidasPendientes,
      definicionesSinOcurrenciaEnPeriodo: definiciones.filter((def) =>
        sinOcurrenciaEnPeriodo.has(def.id),
      ).length,
      definicionesSinPlanificar: sinPlanificar.length,
      descripcionesSinPlanificar: sinPlanificar
        .slice(0, 5)
        .map((def) => def.descripcion),
      definicionesModificadas: definicionesModificadas.length,
      descripcionesModificadas: definicionesModificadas
        .slice(0, 5)
        .map((def) => def.descripcion),
      definicionesRetiradas: definicionesRetiradas.length,
      ultimaActividad: marcaGeneracion?.creadoEn ?? null,
    };
  }

  /** Descarta el borrador completo de un periodo. Accion explicita y auditada. */
  async descartarBorradorMes(payload: unknown) {
    const dto = PeriodoBorradorDTO.parse(payload);
    const { conjuntoId, anio, mes } = dto;

    const eliminadas = await this.prisma.$transaction(async (tx) => {
      const tareas = await tx.tarea.deleteMany({
        where: {
          conjuntoId,
          borrador: true,
          periodoAnio: anio,
          periodoMes: mes,
          tipo: TipoTarea.PREVENTIVA,
        },
      });
      await tx.preventivaExcluidaBorrador.deleteMany({
        where: { conjuntoId, periodoAnio: anio, periodoMes: mes },
      });
      await tx.preventivaBorradorEvento.deleteMany({
        where: { conjuntoId, periodoAnio: anio, periodoMes: mes },
      });
      await (tx as any).preventivaOcurrenciaPlan?.deleteMany({
        where: {
          conjuntoId,
          periodoAnio: anio,
          periodoMes: mes,
          borrador: true,
        },
      });
      return tareas.count;
    });

    await this.auditoria.registrar({
      modulo: ModuloAuditoria.CRONOGRAMA,
      entidad: EntidadAuditoria.CRONOGRAMA_PERIODO,
      entidadId: `${conjuntoId}-${anio}-${mes}`,
      accion: AccionAuditoria.ELIMINAR_CRONOGRAMA,
      conjuntoId,
      actor: this.actor,
      descripcion: `Se descarto el borrador de ${mes}/${anio} (${eliminadas} tarea(s)).`,
      periodoAnio: anio,
      periodoMes: mes,
      metadataJson: { eliminadas },
    });

    return { ok: true, eliminadas };
  }

  private async existeBorradorPreventivoMes(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;
    const total = await this.prisma.tarea.count({
      where: {
        conjuntoId,
        periodoAnio: anio,
        periodoMes: mes,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
      },
    });
    if (total > 0) return true;
    const repo = (this.prisma as any).preventivaOcurrenciaPlan;
    if (!repo?.count) return false;
    const ocurrencias = await repo.count({
      where: {
        conjuntoId,
        periodoAnio: anio,
        periodoMes: mes,
        borrador: true,
      },
    });
    return ocurrencias > 0;
  }

  private async resolverSupervisorId(supervisorId: string): Promise<string> {
    const sid = supervisorId;

    const supervisor = await this.prisma.supervisor.findUnique({
      where: { id: sid },
      select: { id: true },
    });
    if (supervisor) return sid;

    const usuario = await this.prisma.usuario.findUnique({
      where: { id: sid },
      select: { id: true, rol: true },
    });

    if (!usuario) {
      const e: any = new Error(
        "El supervisor seleccionado no existe. Actualiza la lista e inténtalo de nuevo.",
      );
      e.status = 400;
      throw e;
    }

    if (usuario.rol !== Rol.supervisor) {
      const e: any = new Error(
        "El usuario seleccionado no tiene perfil de supervisor. Verifica la selección.",
      );
      e.status = 400;
      throw e;
    }

    const empresa = await this.prisma.empresa.findFirst({ select: { nit: true } });
    if (!empresa) {
      const e: any = new Error(
        "No hay una empresa configurada para asociar el supervisor. Si el problema continúa, contacta al área de TI.",
      );
      e.status = 500;
      throw e;
    }

    try {
      await this.prisma.supervisor.create({
        data: {
          id: sid,
          empresaId: empresa.nit,
        },
      });
    } catch (err: any) {
      if (!(err instanceof Prisma.PrismaClientKnownRequestError) || err.code !== "P2002") {
        throw err;
      }
    }

    return sid;
  }

  private validarProgramacionFrecuencia(params: {
    frecuencia: Frecuencia;
    diaSemanaProgramado?: DiaSemana | null;
    diaMesProgramado?: number | null;
    fechasProgramadasJson?: string[] | null;
  }) {
    const {
      frecuencia,
      diaSemanaProgramado,
      diaMesProgramado,
      fechasProgramadasJson,
    } = params;

    if (frecuencia === Frecuencia.SEMANAL && !diaSemanaProgramado) {
      throw new Error("Las preventivas semanales deben tener un día programado.");
    }

    if (frecuencia === Frecuencia.QUINCENAL && !diaSemanaProgramado) {
      throw new Error("Las preventivas quincenales deben tener un día de la semana programado.");
    }

    if (frecuencia === Frecuencia.MENSUAL && !diaMesProgramado) {
      throw new Error("Las preventivas mensuales deben tener un día del mes programado.");
    }

    if (
      (frecuencia === Frecuencia.BIMESTRAL ||
        frecuencia === Frecuencia.TRIMESTRAL ||
        frecuencia === Frecuencia.SEMESTRAL ||
        frecuencia === Frecuencia.ANUAL) &&
      !(fechasProgramadasJson?.length)
    ) {
      throw new Error(
        "Esta frecuencia requiere al menos una fecha programada seleccionada desde el calendario.",
      );
    }

    const requeridas = this.fechasRequeridasPorFrecuencia(frecuencia);
    if (requeridas != null) {
      const actuales = fechasProgramadasJson?.length ?? 0;
      if (actuales < requeridas) {
        throw new Error(
          `Faltan ${requeridas - actuales} fecha(s) para completar la frecuencia ${frecuencia}.`,
        );
      }
      if (actuales > requeridas) {
        throw new Error(
          `No puedes registrar más de ${requeridas} fecha(s) para la frecuencia ${frecuencia}.`,
        );
      }
    }
  }

  private fechasRequeridasPorFrecuencia(frecuencia: Frecuencia): number | null {
    switch (frecuencia) {
      case Frecuencia.BIMESTRAL:
        return 2;
      case Frecuencia.TRIMESTRAL:
        return 3;
      case Frecuencia.SEMESTRAL:
        return 2;
      case Frecuencia.ANUAL:
        return 1;
      default:
        return null;
    }
  }

  private validarVentanaPublicacion(params: {
    anio: number;
    mes: number;
    diasAnticipacion?: number;
    ahora?: Date;
  }) {
    const { anio, mes, diasAnticipacion = 7, ahora = new Date() } = params;

    const inicioPeriodo = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
    const apertura = new Date(inicioPeriodo);
    apertura.setDate(apertura.getDate() - diasAnticipacion);

    if (+ahora < +apertura) {
      const ymd = (d: Date) =>
        `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(
          d.getDate(),
        ).padStart(2, "0")}`;

      throw new Error(
        `El cronograma ${anio}-${String(mes).padStart(2, "0")} solo se puede publicar desde ${ymd(apertura)} (7 días antes del inicio del periodo: ${ymd(inicioPeriodo)}).`,
      );
    }
  }

  private normalizarListaStrings(values: Array<string | null | undefined>) {
    return values.map((v) => String(v ?? "").trim()).filter((v) => v.length > 0);
  }

  private metadataAsObject(value: Prisma.JsonValue | null | undefined): Record<string, unknown> {
    return value && typeof value === "object" && !Array.isArray(value)
      ? ({ ...(value as Record<string, unknown>) })
      : {};
  }

  private leerDivisionManualExcluida(value: Prisma.JsonValue | null | undefined): DivisionManualExcluida | null {
    const root = this.metadataAsObject(value);
    const raw = root.divisionManual;
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
    const record = raw as Record<string, unknown>;
    const bloquesRaw = Array.isArray(record.bloques) ? record.bloques : [];
    const bloques: BloqueExcluidaManual[] = [];
    for (let index = 0; index < bloquesRaw.length; index++) {
      const item = bloquesRaw[index];
      if (!item || typeof item !== "object" || Array.isArray(item)) continue;
      const block = item as Record<string, unknown>;
      const duracionMinutos = Number(block.duracionMinutos ?? 0);
      if (!Number.isFinite(duracionMinutos) || duracionMinutos <= 0) continue;
      bloques.push({
          id: String(block.id ?? `b${index + 1}`),
          orden: Number(block.orden ?? index + 1),
          duracionMinutos: Math.max(1, Math.round(duracionMinutos)),
          estado: String(block.estado ?? "PENDIENTE") === "AGENDADO" ? "AGENDADO" : "PENDIENTE",
          tareaProgramadaId:
            block.tareaProgramadaId == null ? null : Number(block.tareaProgramadaId),
          fechaInicio: block.fechaInicio == null ? null : String(block.fechaInicio),
          fechaFin: block.fechaFin == null ? null : String(block.fechaFin),
      });
    }
    bloques.sort((a, b) => a.orden - b.orden);
    if (!bloques.length) return null;
    return {
      activa: record.activa !== false,
      bloques,
      actualizadaEn: String(record.actualizadaEn ?? new Date().toISOString()),
    };
  }

  private construirMetadataConDivisionManual(
    base: Prisma.JsonValue | null | undefined,
    division: DivisionManualExcluida | null,
  ): Prisma.InputJsonValue {
    const root = this.metadataAsObject(base);
    if (division == null) {
      delete root.divisionManual;
      return root as Prisma.InputJsonValue;
    }
    root.divisionManual = {
      activa: division.activa,
      actualizadaEn: division.actualizadaEn,
      bloques: division.bloques.map((bloque) => ({
        id: bloque.id,
        orden: bloque.orden,
        duracionMinutos: bloque.duracionMinutos,
        estado: bloque.estado,
        tareaProgramadaId: bloque.tareaProgramadaId ?? null,
        fechaInicio: bloque.fechaInicio ?? null,
        fechaFin: bloque.fechaFin ?? null,
      })),
    } satisfies Prisma.InputJsonValue;
    return root as Prisma.InputJsonValue;
  }

  private resolverBloqueDivision(
    division: DivisionManualExcluida | null,
    bloqueId: string,
  ) {
    if (!division?.activa) return null;
    return division.bloques.find((bloque) => bloque.id === bloqueId) ?? null;
  }

  private async registrarEventoBorrador(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    tipo: string;
    detalle?: string;
    tareaId?: number | null;
    excluidaId?: number | null;
    metadataJson?: Prisma.InputJsonValue;
    /** Accion de auditoria a espejar. Si se omite, el evento solo vive en la bitacora del borrador. */
    accionAuditoria?: string;
    origenAuditoria?: string;
  }) {
    await this.prisma.preventivaBorradorEvento.create({
      data: {
        conjuntoId: params.conjuntoId,
        periodoAnio: params.periodoAnio,
        periodoMes: params.periodoMes,
        tipo: params.tipo,
        detalle: params.detalle,
        tareaId: params.tareaId ?? null,
        excluidaId: params.excluidaId ?? null,
        actorId: this.actor?.id ?? null,
        actorRol: this.actor?.rol ?? null,
        metadataJson: params.metadataJson,
      },
    });

    if (!params.accionAuditoria) return;

    const esExcluida = params.excluidaId != null;
    await this.auditoria.registrar({
      modulo: esExcluida ? ModuloAuditoria.EXCLUIDA : ModuloAuditoria.TAREA,
      entidad: esExcluida ? EntidadAuditoria.EXCLUIDA_BORRADOR : EntidadAuditoria.TAREA,
      entidadId: (params.excluidaId ?? params.tareaId ?? 0),
      accion: params.accionAuditoria,
      conjuntoId: params.conjuntoId,
      actor: this.actor,
      origen: params.origenAuditoria,
      descripcion: params.detalle ?? params.tipo,
      periodoAnio: params.periodoAnio,
      periodoMes: params.periodoMes,
      metadataJson: params.metadataJson,
    });
  }

  /** Atajo para auditar una accion sobre una tarea del cronograma. */
  private async auditarTarea(params: {
    tareaId: number;
    conjuntoId: string;
    accion: string;
    descripcion: string;
    periodoAnio?: number | null;
    periodoMes?: number | null;
    datosAntes?: unknown;
    datosDespues?: unknown;
    metadataJson?: unknown;
  }) {
    await this.auditoria.registrar({
      modulo: ModuloAuditoria.TAREA,
      entidad: EntidadAuditoria.TAREA,
      entidadId: params.tareaId,
      accion: params.accion,
      conjuntoId: params.conjuntoId,
      actor: this.actor,
      descripcion: params.descripcion,
      periodoAnio: params.periodoAnio ?? null,
      periodoMes: params.periodoMes ?? null,
      datosAntes: params.datosAntes,
      datosDespues: params.datosDespues,
      metadataJson: params.metadataJson,
    });
  }

  private async crearExcluida(snapshot: ExcluidaSnapshot) {
    const created = await this.prisma.preventivaExcluidaBorrador.create({
      data: {
        conjuntoId: snapshot.conjuntoId,
        periodoAnio: snapshot.periodoAnio,
        periodoMes: snapshot.periodoMes,
        defId: snapshot.defId ?? null,
        origenTareaId: snapshot.origenTareaId ?? null,
        tareaProgramadaId: snapshot.tareaProgramadaId ?? null,
        ocurrenciaPlanId: snapshot.ocurrenciaPlanId ?? null,
        descripcion: snapshot.descripcion,
        frecuencia: snapshot.frecuencia ?? null,
        diaSemanaProgramado: snapshot.diaSemanaProgramado ?? null,
        prioridad: snapshot.prioridad,
        duracionMinutos: Math.max(1, snapshot.duracionMinutos),
        fechaObjetivo: snapshot.fechaObjetivo,
        ubicacionId: snapshot.ubicacionId,
        ubicacionNombre: snapshot.ubicacionNombre ?? null,
        elementoId: snapshot.elementoId,
        elementoNombre: snapshot.elementoNombre ?? null,
        supervisorId: snapshot.supervisorId ?? null,
        supervisorNombre: snapshot.supervisorNombre ?? null,
        operariosIds: snapshot.operariosIds ?? [],
        operariosNombres: snapshot.operariosNombres ?? [],
        motivoTipo: snapshot.motivoTipo,
        motivoMensaje: snapshot.motivoMensaje ?? null,
        metadataJson: snapshot.metadataJson,
      },
    });

    if (this.rastreoExcluidas) this.excluidasDeLaCorrida.push(created);

    await this.registrarEventoBorrador({
      conjuntoId: snapshot.conjuntoId,
      periodoAnio: snapshot.periodoAnio,
      periodoMes: snapshot.periodoMes,
      tipo: `EXCLUIDA_${snapshot.motivoTipo}`,
      accionAuditoria: AccionAuditoria.CREAR,
      origenAuditoria: OrigenAuditoria.SCHEDULER,
      detalle: snapshot.motivoMensaje ?? undefined,
      excluidaId: created.id,
      tareaId: snapshot.tareaProgramadaId ?? snapshot.origenTareaId ?? null,
      metadataJson: snapshot.metadataJson,
    });

    if (snapshot.ocurrenciaPlanId) {
      await (this.prisma as any).preventivaOcurrenciaPlan?.updateMany({
        where: { id: snapshot.ocurrenciaPlanId },
        data: {
          estado: "SIN_PROGRAMAR",
          motivoCodigo: snapshot.motivoTipo,
          motivoMensaje: snapshot.motivoMensaje ?? null,
        },
      });
    }

    return created;
  }

  private async cargarSnapshotDefinicion(defId: number, conjuntoId: string) {
    const def = await this.prisma.definicionTareaPreventiva.findFirst({
      where: { id: defId, conjuntoId },
      include: {
        operarios: { include: { usuario: { select: { nombre: true } } } },
        necesidades: {
          include: { operario: { include: { usuario: { select: { nombre: true } } } } },
        },
        supervisor: { include: { usuario: { select: { nombre: true } } } },
        ubicacion: { select: { nombre: true } },
        elemento: { include: elementoParentChainInclude },
      },
    });
    if (!def) return null;
    return def;
  }

  private async crearExcluidaDesdeDefinicion(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    defId: number;
    fechaObjetivo: Date;
    duracionMinutos: number;
    motivoTipo: ExclusionMotivoTipo;
    motivoMensaje?: string;
    metadataJson?: Prisma.InputJsonValue;
    ocurrenciaPlanId?: string | null;
  }) {
    const def = await this.cargarSnapshotDefinicion(params.defId, params.conjuntoId);
    if (!def) return null;

    const { ids: operariosIds, nombres: operariosNombres } =
      this.operariosSnapshotDeDefinicion(def as any);

    return this.crearExcluida({
      conjuntoId: params.conjuntoId,
      periodoAnio: params.periodoAnio,
      periodoMes: params.periodoMes,
      defId: def.id,
      ocurrenciaPlanId: params.ocurrenciaPlanId ?? null,
      descripcion: def.descripcion,
      frecuencia: def.frecuencia,
      diaSemanaProgramado: def.diaSemanaProgramado ?? null,
      prioridad: Number((def as any).prioridad ?? 2),
      duracionMinutos: params.duracionMinutos,
      fechaObjetivo: params.fechaObjetivo,
      ubicacionId: def.ubicacionId,
      ubicacionNombre: def.ubicacion?.nombre ?? null,
      elementoId: def.elementoId,
      elementoNombre: construirRutaElemento(def.elemento as any) ?? null,
      supervisorId: def.supervisorId ?? null,
      supervisorNombre: def.supervisor?.usuario?.nombre ?? null,
      operariosIds,
      operariosNombres,
      motivoTipo: params.motivoTipo,
      motivoMensaje: params.motivoMensaje,
      metadataJson: params.metadataJson,
    });
  }

  private async crearExcluidaDesdeTarea(params: {
    tareaId: number;
    motivoTipo: ExclusionMotivoTipo;
    motivoMensaje?: string;
    metadataJson?: Prisma.InputJsonValue;
    duracionMinutos?: number;
    fechaObjetivo?: Date;
  }) {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: params.tareaId },
      include: {
        operarios: { include: { usuario: { select: { nombre: true } } } },
        supervisor: { include: { usuario: { select: { nombre: true } } } },
        ubicacion: { select: { nombre: true } },
        elemento: { include: elementoParentChainInclude },
      },
    });
    if (!tarea || !tarea.conjuntoId) return null;

    return this.crearExcluida({
      conjuntoId: tarea.conjuntoId,
      periodoAnio: tarea.periodoAnio ?? tarea.fechaInicio.getFullYear(),
      periodoMes: tarea.periodoMes ?? tarea.fechaInicio.getMonth() + 1,
      origenTareaId: tarea.id,
      defId: tarea.definicionId ?? null,
      ocurrenciaPlanId: tarea.ocurrenciaPlanId ?? null,
      descripcion: tarea.descripcion,
      frecuencia: tarea.frecuencia,
      diaSemanaProgramado: tarea.diaSemanaProgramado ?? null,
      prioridad: tarea.prioridad,
      duracionMinutos: params.duracionMinutos ?? tarea.duracionMinutos,
      fechaObjetivo:
        params.fechaObjetivo ?? tarea.fechaInicioOriginal ?? tarea.fechaInicio,
      ubicacionId: tarea.ubicacionId,
      ubicacionNombre: tarea.ubicacion?.nombre ?? null,
      elementoId: tarea.elementoId,
      elementoNombre: construirRutaElemento(tarea.elemento as any) ?? null,
      supervisorId: tarea.supervisorId ?? null,
      supervisorNombre: tarea.supervisor?.usuario?.nombre ?? null,
      operariosIds: tarea.operarios.map((o) => o.id),
      operariosNombres: tarea.operarios
        .map((o) => o.usuario?.nombre ?? "")
        .filter((name) => name.trim().length > 0),
      motivoTipo: params.motivoTipo,
      motivoMensaje: params.motivoMensaje,
      metadataJson: params.metadataJson,
    });
  }

  /**
   * Las tareas de menor prioridad desplazadas por el generador dejan de ocupar
   * agenda y pasan a la bandeja de excluidas; no deben quedar como filas ocultas
   * en estado PENDIENTE_REPROGRAMACION dentro del borrador.
   */
  private async moverReemplazadasAExcluidas(params: {
    tareaIds: number[];
    reemplazadaPorDefId: number;
    reemplazadaPorDescripcion: string;
  }) {
    const ids = Array.from(new Set(params.tareaIds));
    for (const tareaId of ids) {
      const excluida = await this.crearExcluidaDesdeTarea({
        tareaId,
        motivoTipo: "REEMPLAZO_PRIORIDAD",
        motivoMensaje:
          `Fue desplazada automáticamente por la tarea prioritaria ` +
          `'${params.reemplazadaPorDescripcion}'.`,
        metadataJson: {
          reemplazadaPorDefId: params.reemplazadaPorDefId,
          reemplazadaPorDescripcion: params.reemplazadaPorDescripcion,
        },
      });
      if (excluida) {
        await this.prisma.tarea.delete({ where: { id: tareaId } });
      }
    }
  }

  /**
   * Regla: la misma tarea (definición) no se repite dos veces el mismo día.
   * Los bloques de una misma ocurrencia (o grupo) sí pueden compartir día.
   * Lanza un error accionable si el día ya tiene otra ocurrencia.
   */
  private async validarNoRepiteDefinicionEnDia(params: {
    conjuntoId: string;
    fecha: Date;
    identidad: IdentidadTareaDia;
    excluirTareaId?: number;
  }) {
    const { conjuntoId, fecha, identidad, excluirTareaId } = params;
    const inicioDia = new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate());
    const finDia = new Date(
      fecha.getFullYear(),
      fecha.getMonth(),
      fecha.getDate(),
      23,
      59,
      59,
      999,
    );
    const mismaTarea: Prisma.TareaWhereInput[] = [];
    if (identidad.definicionId != null) {
      mismaTarea.push({ definicionId: identidad.definicionId });
    }
    if (
      identidad.descripcion &&
      identidad.ubicacionId != null &&
      identidad.elementoId != null
    ) {
      mismaTarea.push({
        descripcion: { equals: identidad.descripcion, mode: "insensitive" },
        ubicacionId: identidad.ubicacionId,
        elementoId: identidad.elementoId,
      });
    }
    if (!mismaTarea.length) return;

    const existentes = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        fechaInicio: { gte: inicioDia, lte: finDia },
        ...(excluirTareaId != null ? { id: { not: excluirTareaId } } : {}),
        OR: mismaTarea,
      },
      select: { id: true, ocurrenciaPlanId: true, grupoPlanId: true },
    });
    const propia = identidad.ocurrenciaPlanId ?? identidad.grupoPlanId ?? null;
    const otra = existentes.find((tarea) => {
      const firma = tarea.ocurrenciaPlanId ?? tarea.grupoPlanId ?? `tarea:${tarea.id}`;
      return propia == null || firma !== propia;
    });
    if (otra) {
      throw new Error(
        `"${identidad.descripcion ?? "Esta tarea"}" ya está programada ese día. ` +
          "La misma tarea no se repite dos veces el mismo día: elige otro día.",
      );
    }
  }

  private identidadDeExcluida(excluida: {
    id: number;
    defId?: number | null;
    descripcion?: string | null;
    ubicacionId?: number | null;
    elementoId?: number | null;
    ocurrenciaPlanId?: string | null;
  }): IdentidadTareaDia {
    return {
      definicionId: excluida.defId ?? null,
      descripcion: excluida.descripcion ?? null,
      ubicacionId: excluida.ubicacionId ?? null,
      elementoId: excluida.elementoId ?? null,
      ocurrenciaPlanId: excluida.ocurrenciaPlanId ?? `excluida:${excluida.id}`,
    };
  }

  private async validarSlotPreventivaBorrador(params: {
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
    operariosIds: string[];
    excluirTareaId?: number;
    /** Si se envía, también se valida que la tarea no se repita ese día. */
    identidad?: IdentidadTareaDia;
  }) {
    const { conjuntoId, fechaInicio, fechaFin, operariosIds, excluirTareaId } = params;

    if (fechaFin < fechaInicio) {
      throw new Error("fechaFin debe ser mayor o igual a fechaInicio");
    }

    const validacionIntervalo = await validarIntervaloProgramacion({
      prisma: this.prisma,
      conjuntoId,
      fechaInicio,
      fechaFin,
      operariosIds,
    });
    if (!validacionIntervalo.ok) throw new Error(validacionIntervalo.mensaje);

    if (params.identidad) {
      await this.validarNoRepiteDefinicionEnDia({
        conjuntoId,
        fecha: fechaInicio,
        identidad: params.identidad,
        excluirTareaId,
      });
    }

    const inicioEsFestivo = await isFestivoDate({
      prisma: this.prisma,
      fecha: fechaInicio,
      pais: "CO",
    });
    if (inicioEsFestivo) {
      // La plaza (necesidad operativa) de cada operario decide si trabaja
      // festivos, con su propio horario -no depende del rol-.
      // validarIntervaloProgramacion (arriba) ya validó que este horario
      // exacto cae dentro de la ventana festiva de la plaza.
      const puedenTrabajarFestivo =
        operariosIds.length > 0 &&
        (await operariosPuedenTrabajarFestivo({
          prisma: this.prisma,
          conjuntoId,
          operariosIds,
        }));
      if (!puedenTrabajarFestivo) {
        throw new Error("No se permite programar tareas preventivas en festivos.");
      }
    }

    if (operariosIds.length) {
      const disponibilidad = await validarOperariosDisponiblesEnFecha({
        prisma: this.prisma,
        fecha: fechaInicio,
        operariosIds,
      });
      if (!disponibilidad.ok) {
        throw new Error(
          await construirMensajeSinDisponibilidadOperarios(
            this.prisma,
            disponibilidad.noDisponibles,
          ),
        );
      }

      for (const opId of operariosIds) {
        const haySolape = await existeSolapeParaOperario(this.prisma, {
          conjuntoId,
          operarioId: opId,
          fechaInicio,
          fechaFin,
          soloBorrador: true,
          excluirTareaId,
        });

        if (haySolape) {
          const nombre = await getOperarioNombre(this.prisma, opId);
          throw new Error(`Solape de agenda con operario ${nombre}`);
        }
      }

      await validarLimiteSemanalOperarios({
        prisma: this.prisma,
        conjuntoId,
        operariosIds,
        fechaInicio,
        duracionMinutos: Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000)),
        excluirTareaId,
      });
    }
  }

  private async validarHorarioBloqueBorrador(params: {
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
  }) {
    const validacion = await validarIntervaloProgramacion({
      prisma: this.prisma,
      ...params,
      operariosIds: [],
    });
    if (!validacion.ok) throw new Error(validacion.mensaje);
  }

  private async validarDivisionSoloPorDescanso(params: {
    conjuntoId: string;
    bloques: BloqueProgramacion[];
  }) {
    if (params.bloques.length <= 1) return;
    if (params.bloques.length !== 2) {
      throw new Error(
        "Una tarea solo puede dividirse en dos bloques alrededor del almuerzo.",
      );
    }

    const bloques = [...params.bloques].sort(
      (a, b) => +a.fechaInicio - +b.fechaInicio,
    );
    if (
      dayKey(bloques[0].fechaInicio) !== dayKey(bloques[1].fechaInicio) ||
      dayKey(bloques[0].fechaFin) !== dayKey(bloques[1].fechaFin)
    ) {
      throw new Error("Una tarea no puede dividirse entre días distintos.");
    }

    const dia = dateToDiaSemana(bloques[0].fechaInicio);
    const horario = await this.prisma.conjuntoHorario.findUnique({
      where: { conjuntoId_dia: { conjuntoId: params.conjuntoId, dia } },
      select: { descansoInicio: true, descansoFin: true },
    });
    if (!horario?.descansoInicio || !horario.descansoFin) {
      throw new Error(
        "La jornada no tiene un descanso configurado que permita dividir la tarea.",
      );
    }

    const inicioDescanso = toMin(horario.descansoInicio);
    const finDescanso = toMin(horario.descansoFin);
    if (
      toMinOfDay(bloques[0].fechaFin) !== inicioDescanso ||
      toMinOfDay(bloques[1].fechaInicio) !== finDescanso
    ) {
      throw new Error(
        "Los dos bloques deben terminar antes del almuerzo y continuar justo después.",
      );
    }
  }

  private async validarEdicionMantieneDivisionAlmuerzo(params: {
    tareaId: number;
    conjuntoId: string;
    ocurrenciaPlanId?: string | null;
    grupoPlanId?: string | null;
    fechaInicio: Date;
    fechaFin: Date;
  }) {
    const filtroGrupo = params.ocurrenciaPlanId
      ? { ocurrenciaPlanId: params.ocurrenciaPlanId }
      : params.grupoPlanId
        ? { grupoPlanId: params.grupoPlanId }
        : null;
    if (!filtroGrupo) return;

    const hermanas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: params.conjuntoId,
        ...filtroGrupo,
        id: { not: params.tareaId },
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
      },
      select: { fechaInicio: true, fechaFin: true },
    });
    if (!hermanas.length) return;
    await this.validarDivisionSoloPorDescanso({
      conjuntoId: params.conjuntoId,
      bloques: [
        { fechaInicio: params.fechaInicio, fechaFin: params.fechaFin },
        ...hermanas.map((tarea) => ({
          fechaInicio: tarea.fechaInicio,
          fechaFin: tarea.fechaFin,
        })),
      ],
    });
  }

  private async sugerirHuecosParaExcluidaCore(params: {
    conjuntoId: string;
    excluida: {
      id: number;
      periodoAnio: number;
      periodoMes: number;
      descripcion: string;
      duracionMinutos: number;
      fechaObjetivo: Date;
      operariosIds: string[];
      defId?: number | null;
      ubicacionId?: number | null;
      elementoId?: number | null;
      ocurrenciaPlanId?: string | null;
    };
    fechaPreferida?: Date;
    maxOpciones?: number;
    mismoDiaPrimero?: boolean;
    permitirSplitMismoDia?: boolean;
    permitirDivisionFlexible?: boolean;
  }) {
    const {
      conjuntoId,
      excluida,
      fechaPreferida,
      maxOpciones = 8,
      mismoDiaPrimero = true,
      permitirSplitMismoDia = true,
      permitirDivisionFlexible = true,
    } = params;

    // Ventana de búsqueda: la de la(s) plaza(s) de los operarios de la
    // excluida (o el horario general del conjunto si ninguno tiene plaza
    // con horario especial -> comportamiento previo intacto).
    const horariosPorDia = await this.horariosPorDiaParaOperarios(
      conjuntoId,
      excluida.operariosIds,
    );

    const inicioMes = new Date(excluida.periodoAnio, excluida.periodoMes - 1, 1, 0, 0, 0, 0);
    const finMes = new Date(excluida.periodoAnio, excluida.periodoMes, 0, 23, 59, 59, 999);
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioMes,
      fin: finMes,
    });
    // La plaza de cada operario decide si trabaja festivos (no el rol, ver
    // ConjuntoNecesidadOperario.trabajaFestivos). Si puede, se trata el día
    // como "no festivo" para que esta sugerencia use el horario normal del
    // día de semana como aproximación -el slot final que el usuario elija
    // se revalida por completo (horario festivo real incluido) en
    // validarSlotPreventivaBorrador antes de guardarse-.
    const puedeTrabajarFestivoExcluida =
      excluida.operariosIds.length > 0 &&
      (await operariosPuedenTrabajarFestivo({
        prisma: this.prisma,
        conjuntoId,
        operariosIds: excluida.operariosIds,
      }));
    const festivosSetEfectivo = puedeTrabajarFestivoExcluida
      ? new Set<string>()
      : festivosSet;

    const fechas = enumerateDays(inicioMes, finMes);
    const preferida = fechaPreferida ?? excluida.fechaObjetivo;
    fechas.sort((a, b) => {
      const aSame = dayKey(a) == dayKey(preferida) ? 0 : 1;
      const bSame = dayKey(b) == dayKey(preferida) ? 0 : 1;
      if (mismoDiaPrimero && aSame != bSame) return aSame - bSame;
      return a.getTime() - b.getTime();
    });

    const opciones: Array<{
      fecha: string;
      fechaInicio: string;
      fechaFin: string;
      duracionMinutos: number;
      tipoSugerencia: "MISMO_DIA" | "MISMO_MES" | "DIVIDIDA";
      requiereDivision: boolean;
      diasUtilizados: number;
      bloques: Array<{
        fecha: string;
        fechaInicio: string;
        fechaFin: string;
        duracionMinutos: number;
      }>;
    }> = [];

    const pushOpcion = (bloquesPlan: BloqueProgramacion[]) => {
      if (!bloquesPlan.length || opciones.length >= maxOpciones) return;
      const bloques = bloquesPlan
        .map((bloque) => ({
          fecha: dayKey(bloque.fechaInicio),
          fechaInicio: bloque.fechaInicio.toISOString(),
          fechaFin: bloque.fechaFin.toISOString(),
          duracionMinutos: Math.max(
            1,
            Math.round((bloque.fechaFin.getTime() - bloque.fechaInicio.getTime()) / 60000),
          ),
        }))
        .sort((a, b) => a.fechaInicio.localeCompare(b.fechaInicio));
      const primera = bloques[0];
      const ultima = bloques[bloques.length - 1];
      const diasUtilizados = new Set(bloques.map((bloque) => bloque.fecha)).size;
      const requiereDivision = bloques.length > 1;
      const firma = bloques
        .map((bloque) => `${bloque.fechaInicio}|${bloque.fechaFin}`)
        .join(";");
      if (opciones.some((item) => item.bloques.map((b) => `${b.fechaInicio}|${b.fechaFin}`).join(";") === firma)) {
        return;
      }

      opciones.push({
        fecha: primera.fecha,
        fechaInicio: primera.fechaInicio,
        fechaFin: ultima.fechaFin,
        duracionMinutos: bloques.reduce((acc, bloque) => acc + bloque.duracionMinutos, 0),
        tipoSugerencia: requiereDivision
          ? "DIVIDIDA"
          : primera.fecha === dayKey(preferida)
            ? "MISMO_DIA"
            : "MISMO_MES",
        requiereDivision,
        diasUtilizados,
        bloques,
      });
    };

    for (const dia of fechas) {
      if (opciones.length >= maxOpciones) break;
      const key = dayKey(dia);
      if (festivosSetEfectivo.has(key)) continue;

      const horario = horariosPorDia.get(dateToDiaSemana(dia));
      if (!horario) continue;

      const disponibilidad = excluida.operariosIds.length
        ? await validarOperariosDisponiblesEnFecha({
            prisma: this.prisma,
            fecha: dia,
            operariosIds: excluida.operariosIds,
          })
        : { ok: true, noDisponibles: [] as string[] };
      if (!disponibilidad.ok) continue;

      const bloqueos = [
        ...buildBloqueosPorDescanso(horario),
        ...(await buildBloqueosPorPatronJornada({
          prisma: this.prisma,
          conjuntoId,
          fechaDia: dia,
          horarioDia: horario,
          operariosIds: excluida.operariosIds,
        })),
      ];

      let ocupadosGlobal: Intervalo[] = [];
      if (excluida.operariosIds.length) {
        const agenda = await buildAgendaPorOperarioDia({
          prisma: this.prisma,
          conjuntoId,
          fechaDia: dia,
          operariosIds: excluida.operariosIds,
          incluirBorrador: true,
          bloqueosGlobales: bloqueos,
          excluirEstados: ["PENDIENTE_REPROGRAMACION"],
        });

        const all: Intervalo[] = [];
        for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
        ocupadosGlobal = mergeIntervalos(all);
      } else {
        ocupadosGlobal = mergeIntervalos(
          bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
        );
      }

      const bloques = buscarHuecoDiaConSplitEarliest({
        startMin: horario.startMin,
        endMin: horario.endMin,
        durMin: excluida.duracionMinutos,
        ocupados: ocupadosGlobal,
        bloqueos,
        desiredStartMin: dayKey(dia) === dayKey(preferida)
          ? Math.max(horario.startMin, toMinOfDay(preferida))
          : horario.startMin,
        maxBloques: permitirSplitMismoDia ? 2 : 1,
        splitSoloPorDescanso: permitirSplitMismoDia,
      });

      if (bloques?.length) {
        const bloquesPlan = bloques.map((bloque) => ({
          fechaInicio: toDateAtMin(dia, bloque.i),
          fechaFin: toDateAtMin(dia, bloque.f),
        }));

        try {
          for (const bloque of bloquesPlan) {
            await this.validarSlotPreventivaBorrador({
              conjuntoId,
              fechaInicio: bloque.fechaInicio,
              fechaFin: bloque.fechaFin,
              operariosIds: excluida.operariosIds,
              identidad: this.identidadDeExcluida(excluida),
            });
          }
          pushOpcion(bloquesPlan);
        } catch {
          // seguir buscando otras alternativas
        }
      }

      if (!permitirDivisionFlexible || opciones.length >= maxOpciones) continue;

      const planDividido = await this.construirPlanFlexibleExcluida({
        conjuntoId,
        excluida,
        fechas,
        horariosPorDia,
        festivosSet: festivosSetEfectivo,
        preferida,
        startIndex: fechas.findIndex((f) => dayKey(f) === key),
      });
      if (planDividido.length) pushOpcion(planDividido);
    }

    return {
      excluidaId: excluida.id,
      descripcion: excluida.descripcion,
      opciones,
    };
  }

  /**
   * Reparte `duracionMinutos` sobre los dias candidatos, en orden, tomando los huecos
   * libres que encuentre. Es el motor comun del rescate del scheduler y de las
   * sugerencias de division para tareas excluidas.
   *
   * Devuelve el plan completo o `[]` si no logra cubrir toda la duracion.
   */
  private async construirPlanEnRango(params: {
    conjuntoId: string;
    duracionMinutos: number;
    operariosIds: string[];
    dias: Date[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
    // Set SIN filtrar de festivos del mes (todos, aunque `festivosSet` ya
    // venga vacío por poder trabajarlos) + el horario festivo de la plaza.
    // Cuando se pasan, un día festivo que sobrevive el filtro de arriba usa
    // este horario en vez del horario normal del día de semana. Sin ellos
    // (llamadores que no los pasan), el comportamiento es idéntico al
    // previo: un festivo permitido usa el horario normal del día.
    festivosSetRaw?: Set<string>;
    festivoHorario?: HorarioDia | null;
    preferida?: Date;
    maxBloquesPorDia?: number;
    permitirMultiDia?: boolean;
    validarLimiteSemanal?: boolean;
    incluirPublicadasEnAgenda?: boolean;
    splitSoloPorDescanso?: boolean;
  }): Promise<BloqueProgramacion[]> {
    const {
      conjuntoId,
      duracionMinutos,
      operariosIds,
      dias,
      horariosPorDia,
      festivosSet,
      festivosSetRaw = new Set<string>(),
      festivoHorario = null,
      preferida,
      maxBloquesPorDia = 3,
      permitirMultiDia = false,
      validarLimiteSemanal = false,
      incluirPublicadasEnAgenda = true,
      splitSoloPorDescanso = true,
    } = params;

    if (duracionMinutos <= 0 || !dias.length) return [];

    // El tope semanal depende de la semana, por eso la cache se indexa por operario + semana.
    const limitePorOperarioSemana = new Map<string, number>();
    const minutosPlanificadosPorSemana = new Map<string, number>();

    let restante = duracionMinutos;
    const plan: BloqueProgramacion[] = [];

    for (const dia of dias) {
      if (restante <= 0) break;

      const key = dayKey(dia);
      if (festivosSet.has(key)) continue;

      const horario = resolverHorarioConFestivo(dia, horariosPorDia, festivosSetRaw, festivoHorario);
      if (!horario) continue;

      const disponibilidad = operariosIds.length
        ? await this.disponibilidadScheduler({
            fecha: dia,
            operariosIds,
          })
        : { ok: true, noDisponibles: [] as string[] };
      if (!disponibilidad.ok) continue;

      const bloqueos = [
        ...buildBloqueosPorDescanso(horario),
        ...(await this.bloqueosPatronScheduler({
          conjuntoId,
          fecha: dia,
          horario,
          operariosIds,
        })),
      ];

      let ocupadosGlobal: Intervalo[] = [];
      if (operariosIds.length) {
        if (this.agendaSchedulerActiva) {
          ocupadosGlobal = this.ocupadosAgendaScheduler({
            fecha: dia,
            operariosIds,
            incluirPublicadas: incluirPublicadasEnAgenda,
            bloqueos,
          });
        } else {
          const agenda = await buildAgendaPorOperarioDia({
            prisma: this.prisma,
            conjuntoId,
            fechaDia: dia,
            operariosIds,
            incluirBorrador: true,
            bloqueosGlobales: bloqueos,
            excluirEstados: ["PENDIENTE_REPROGRAMACION"],
          });

          const all: Intervalo[] = [];
          for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
          ocupadosGlobal = mergeIntervalos(all);
        }
      } else {
        ocupadosGlobal = mergeIntervalos(
          bloqueos.map((bloqueo) => ({ i: bloqueo.startMin, f: bloqueo.endMin })),
        );
      }

      const blocked = mergeIntervalos([
        ...ocupadosGlobal,
        ...bloqueos.map((bloqueo) => ({ i: bloqueo.startMin, f: bloqueo.endMin })),
      ]);
      const libres = freeFromOccupied(horario.startMin, horario.endMin, blocked);
      const desiredStartMin =
        preferida != null && key === dayKey(preferida)
          ? Math.max(horario.startMin, toMinOfDay(preferida))
          : horario.startMin;

      const planDia: BloqueProgramacion[] = [];
      if (splitSoloPorDescanso) {
        const bloquesPermitidos = buscarHuecoDiaConSplitEarliest({
          startMin: horario.startMin,
          endMin: horario.endMin,
          durMin: restante,
          ocupados: ocupadosGlobal,
          bloqueos,
          desiredStartMin,
          maxBloques: 2,
          splitSoloPorDescanso: true,
        });
        if (bloquesPermitidos) {
          planDia.push(
            ...bloquesPermitidos.map((bloque) => ({
              fechaInicio: toDateAtMin(dia, bloque.i),
              fechaFin: toDateAtMin(dia, bloque.f),
            })),
          );
        }
      } else {
        let restanteDia = restante;
        for (const libre of libres) {
          if (restanteDia <= 0) break;
          if (planDia.length >= maxBloquesPorDia) break;

          const inicioMin = Math.max(libre.i, desiredStartMin);
          const capacidad = libre.f - inicioMin;
          if (capacidad <= 0) continue;

          const tomar = Math.min(capacidad, restanteDia);
          const fechaInicio = toDateAtMin(dia, inicioMin);
          const fechaFin = toDateAtMin(dia, inicioMin + tomar);

          planDia.push({ fechaInicio, fechaFin });
          restanteDia -= tomar;
        }
      }

      if (!planDia.length) continue;

      const minutosDia = duracionDeBloques(planDia);
      const claveSemana = dayKey(inicioSemana(planDia[0].fechaInicio));
      const minutosPreviosDelPlan =
        minutosPlanificadosPorSemana.get(claveSemana) ?? 0;
      if (
        validarLimiteSemanal &&
        !(await this.cabeEnLimiteSemanal({
          conjuntoId,
          operariosIds,
          fechaReferencia: planDia[0].fechaInicio,
          minutosAdicionales: minutosPreviosDelPlan + minutosDia,
          horariosPorDia,
          incluirPublicadasEnAgenda,
          cacheLimite: limitePorOperarioSemana,
        }))
      ) {
        continue;
      }

      if (!permitirMultiDia) {
        // Cada dia se evalua por separado: solo vale si cubre la duracion completa.
        if (minutosDia >= duracionMinutos) return planDia;
        continue;
      }

      plan.push(...planDia);
      restante -= minutosDia;
      minutosPlanificadosPorSemana.set(
        claveSemana,
        minutosPreviosDelPlan + minutosDia,
      );
    }

    return restante <= 0
      ? plan.sort((a, b) => +a.fechaInicio - +b.fechaInicio)
      : [];
  }

  /** Calcula la carga de todos los días candidatos con una sola consulta. */
  private async cargaOperariosEnDias(params: {
    conjuntoId: string;
    dias: Date[];
    operariosIds: string[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
  }): Promise<Map<string, number>> {
    const cargas = new Map(params.dias.map((dia) => [dayKey(dia), 0]));
    if (!params.operariosIds.length || !params.dias.length) return cargas;

    if (this.agendaSchedulerActiva) {
      for (const dia of params.dias) {
        const intervalos = this.ocupadosAgendaScheduler({
          fecha: dia,
          operariosIds: params.operariosIds,
          incluirPublicadas: true,
          bloqueos: [],
        });
        cargas.set(
          dayKey(dia),
          intervalos.reduce(
            (total, intervalo) => total + intervalo.f - intervalo.i,
            0,
          ),
        );
      }
      return cargas;
    }

    const inicioPeriodo = new Date(params.dias[0]);
    inicioPeriodo.setHours(0, 0, 0, 0);
    const finPeriodo = new Date(params.dias[params.dias.length - 1]);
    finPeriodo.setHours(23, 59, 59, 999);
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: params.conjuntoId,
        fechaInicio: { lte: finPeriodo },
        fechaFin: { gte: inicioPeriodo },
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        operarios: { some: { id: { in: params.operariosIds } } },
      },
      select: { fechaInicio: true, fechaFin: true },
    });

    const intervalosPorDia = new Map<string, Intervalo[]>();
    for (const tarea of tareas) {
      const clave = dayKey(tarea.fechaInicio);
      if (!cargas.has(clave)) continue;
      const horario = params.horariosPorDia.get(
        dateToDiaSemana(tarea.fechaInicio),
      );
      if (!horario) continue;
      const intervalo = {
        i: Math.max(horario.startMin, toMinOfDay(tarea.fechaInicio)),
        f: Math.min(horario.endMin, toMinOfDay(tarea.fechaFin)),
      };
      if (intervalo.f <= intervalo.i) continue;
      const intervalos = intervalosPorDia.get(clave) ?? [];
      intervalos.push(intervalo);
      intervalosPorDia.set(clave, intervalos);
    }
    for (const [clave, intervalos] of intervalosPorDia) {
      cargas.set(
        clave,
        mergeIntervalos(intervalos).reduce(
          (total, intervalo) => total + intervalo.f - intervalo.i,
          0,
        ),
      );
    }
    return cargas;
  }

  /**
   * Devuelve los días hábiles del mes priorizando primero los que no contienen
   * la misma actividad y, después, cercanía y menor carga. Los días repetidos
   * se conservan como respaldo para no perder cobertura.
   */
  private async diasMesPorAprovechamiento(params: {
    conjuntoId: string;
    fechaObjetivo: Date;
    periodoAnio: number;
    periodoMes: number;
    operariosIds: string[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
    festivosSetRaw?: Set<string>;
    festivoHorario?: HorarioDia | null;
    definicionId: number;
    descripcion: string;
    ubicacionId: number;
    elementoId: number;
  }): Promise<Date[]> {
    const inicio = new Date(params.periodoAnio, params.periodoMes - 1, 1);
    const fin = new Date(params.periodoAnio, params.periodoMes, 0);
    const festivosSetRaw = params.festivosSetRaw ?? new Set<string>();

    const candidatos = enumerateDays(inicio, fin).filter(
      (dia) =>
        dia.getFullYear() === params.periodoAnio &&
        dia.getMonth() + 1 === params.periodoMes &&
        !params.festivosSet.has(dayKey(dia)) &&
        resolverHorarioConFestivo(dia, params.horariosPorDia, festivosSetRaw, params.festivoHorario) !=
          null,
    );
    const cargas = await this.cargaOperariosEnDias({
      conjuntoId: params.conjuntoId,
      dias: candidatos,
      operariosIds: params.operariosIds,
      horariosPorDia: params.horariosPorDia,
    });
    const ocurrenciasMismaDefinicion = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: params.conjuntoId,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
        fechaInicio: {
          gte: inicio,
          lte: new Date(
            fin.getFullYear(),
            fin.getMonth(),
            fin.getDate(),
            23,
            59,
            59,
            999,
          ),
        },
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        OR: [
          { definicionId: params.definicionId },
          // Misma tarea cargada en otra definición (o sin definición).
          {
            descripcion: { equals: params.descripcion, mode: "insensitive" },
            ubicacionId: params.ubicacionId,
            elementoId: params.elementoId,
          },
        ],
      },
      select: {
        id: true,
        fechaInicio: true,
        ocurrenciaPlanId: true,
        grupoPlanId: true,
      },
    });
    const ocurrenciasPorDia = new Map<string, Set<string>>();
    for (const tarea of ocurrenciasMismaDefinicion) {
      const claveDia = dayKey(tarea.fechaInicio);
      const firmas = ocurrenciasPorDia.get(claveDia) ?? new Set<string>();
      firmas.add(
        tarea.ocurrenciaPlanId ?? tarea.grupoPlanId ?? `tarea:${tarea.id}`,
      );
      ocurrenciasPorDia.set(claveDia, firmas);
    }
    const conCarga = candidatos.map((dia) => ({
      dia,
      carga: cargas.get(dayKey(dia)) ?? 0,
      iguales: ocurrenciasPorDia.get(dayKey(dia))?.size ?? 0,
    }));
    const objetivoKey = dayKey(params.fechaObjetivo);

    const ordenar = (lista: typeof conCarga) =>
      [...lista].sort((a, b) => {
        const aObjetivo = dayKey(a.dia) === objetivoKey;
        const bObjetivo = dayKey(b.dia) === objetivoKey;
        if (aObjetivo !== bObjetivo) return aObjetivo ? -1 : 1;

        const distanciaA = Math.abs(+a.dia - +params.fechaObjetivo);
        const distanciaB = Math.abs(+b.dia - +params.fechaObjetivo);
        if (distanciaA !== distanciaB) return distanciaA - distanciaB;

        if (a.carga !== b.carga) return a.carga - b.carga;

        // A igual distancia se usa primero el día futuro y luego el anterior.
        const aFuturo = +a.dia >= +params.fechaObjetivo;
        const bFuturo = +b.dia >= +params.fechaObjetivo;
        if (aFuturo !== bFuturo) return aFuturo ? -1 : 1;
        return +a.dia - +b.dia;
      });

    // Un día que ya tiene esta misma tarea queda descartado como candidato:
    // un operario no debe repetir la misma tarea dos veces el mismo día. Si
    // ningún día del mes queda libre, la ocurrencia queda excluida en vez de
    // duplicarse.
    const sinRepetir = conCarga.filter((item) => item.iguales === 0);

    return ordenar(sinRepetir).map((item) => item.dia);
  }

  /** Elige el primer día balanceado que aloja la tarea con menos fragmentos. */
  private async construirMejorPlanEnDias(params: {
    conjuntoId: string;
    duracionMinutos: number;
    operariosIds: string[];
    dias: Date[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
    festivosSetRaw?: Set<string>;
    festivoHorario?: HorarioDia | null;
    incluirPublicadasEnAgenda: boolean;
  }): Promise<BloqueProgramacion[]> {
    let mejor: BloqueProgramacion[] = [];
    let mejorOrden = Number.MAX_SAFE_INTEGER;

    for (let orden = 0; orden < params.dias.length; orden++) {
      const plan = await this.construirPlanEnRango({
        conjuntoId: params.conjuntoId,
        duracionMinutos: params.duracionMinutos,
        operariosIds: params.operariosIds,
        dias: [params.dias[orden]],
        horariosPorDia: params.horariosPorDia,
        festivosSet: params.festivosSet,
        festivosSetRaw: params.festivosSetRaw,
        festivoHorario: params.festivoHorario,
        maxBloquesPorDia: MAX_BLOQUES_RESCATE_POR_DIA,
        permitirMultiDia: false,
        validarLimiteSemanal: true,
        incluirPublicadasEnAgenda: params.incluirPublicadasEnAgenda,
        splitSoloPorDescanso: true,
      });
      if (!plan.length) continue;
      // Un solo bloque es el óptimo teórico. Como los días ya vienen ordenados
      // por aprovechamiento, consultar el resto del mes no puede mejorarlo.
      if (plan.length === 1) return plan;
      if (
        !mejor.length ||
        plan.length < mejor.length ||
        (plan.length === mejor.length && orden < mejorOrden)
      ) {
        mejor = plan;
        mejorOrden = orden;
      }
    }

    return mejor;
  }

  /**
   * Segunda pasada del scheduler: conserva el dia y los recursos de cada
   * tarea, y reempaca las horas del dia por orden de programacion:
   * categoria (su ordenProgramacion) -> orden interno dentro de la categoria
   * -> prioridad de seleccion -> definicion. Nunca cambia que tareas quedaron
   * seleccionadas ni quien las ejecuta. Las tareas sin categoria activa van al
   * final del dia. Los componentes sin operarios en comun pueden permanecer
   * en paralelo.
   */
  private async reordenarBorradorGeneradoPorCategoria(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
  }): Promise<{ reordenadas: number; componentesSinOrdenar: number }> {
    // Festivos del mes: necesarios para que el reordenamiento use el horario
    // FESTIVO de la plaza (si trabaja festivos) en vez del horario normal de
    // ese día de semana -si no, una tarea creada correctamente en horario
    // festivo terminaba reposicionada aquí dentro del horario normal-.
    const inicioMesReorden = new Date(params.periodoAnio, params.periodoMes - 1, 1);
    const finMesReorden = new Date(params.periodoAnio, params.periodoMes, 0, 23, 59, 59, 999);
    const festivosSetReorden = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioMesReorden,
      fin: finMesReorden,
    });

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: params.conjuntoId,
        periodoAnio: params.periodoAnio,
        periodoMes: params.periodoMes,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
      },
      include: {
        operarios: { select: { id: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
    if (tareas.some((tarea) => !Array.isArray((tarea as any).operarios))) {
      return { reordenadas: 0, componentesSinOrdenar: 0 };
    }

    // Los dos tramos que rodean el almuerzo forman una unidad funcional. Se
    // dejan fijos para que el ordenamiento nunca los separe ni los convierta
    // en huecos arbitrarios. Solo cuentan los bloques de la misma ocurrencia
    // EN EL MISMO DIA: las partes de una tarea de varios dias estan cada una en
    // un dia distinto y si pueden ordenarse como cualquier otra tarea.
    const tareasPorOcurrencia = new Map<string, typeof tareas>();
    for (const tarea of tareas) {
      const base = tarea.ocurrenciaPlanId ?? tarea.grupoPlanId;
      if (!base) continue;
      const clave = `${base}|${dayKey(tarea.fechaInicio)}`;
      const grupo = tareasPorOcurrencia.get(clave) ?? [];
      grupo.push(tarea);
      tareasPorOcurrencia.set(clave, grupo);
    }
    const idsDivisionAlmuerzo = new Set<number>();
    for (const grupo of tareasPorOcurrencia.values()) {
      if (grupo.length <= 1) continue;
      grupo.forEach((tarea) => idsDivisionAlmuerzo.add(tarea.id));
    }
    const tareasReordenables = tareas.filter(
      (tarea) => !idsDivisionAlmuerzo.has(tarea.id),
    );
    if (tareasReordenables.length < 2) {
      return { reordenadas: 0, componentesSinOrdenar: 0 };
    }

    // Categorias vigentes (orden y estado) de las tareas a reordenar: una
    // categoria desactivada se trata como "sin categoria".
    const categoriasIds = Array.from(
      new Set(
        tareasReordenables
          .map((tarea) => tarea.categoriaId)
          .filter((id): id is number => id != null),
      ),
    );
    const categoriasRows = categoriasIds.length
      ? await this.prisma.categoriaTarea.findMany({
          where: { id: { in: categoriasIds } },
          select: { id: true, ordenProgramacion: true, activa: true },
        })
      : [];
    const categorias = new Map(categoriasRows.map((c) => [c.id, c]));
    // `estricto` aplica el orden completo; el reintento solo conserva el orden
    // de categorias y el horario previo dentro de cada una.
    const datosOrden = (
      tarea: (typeof tareas)[number],
      estricto: boolean,
    ): DatosOrdenProgramacion => {
      const categoria =
        tarea.categoriaId != null ? categorias.get(tarea.categoriaId) : undefined;
      const vigente = categoria?.activa ? categoria : undefined;
      return {
        categoriaOrden: vigente?.ordenProgramacion ?? null,
        categoriaId: vigente?.id ?? null,
        ordenEnCategoria: estricto ? tarea.ordenEnCategoria : null,
        prioridad: estricto ? Number(tarea.prioridad ?? 2) : 0,
        definicionId: estricto ? tarea.definicionId : null,
        fechaInicioMs: +tarea.fechaInicio,
        id: tarea.id,
      };
    };
    const porDia = new Map<string, typeof tareas>();
    for (const tarea of tareasReordenables) {
      const clave = dayKey(tarea.fechaInicio);
      const lista = porDia.get(clave) ?? [];
      lista.push(tarea);
      porDia.set(clave, lista);
    }

    // La cache queda solo con compromisos fijos (publicadas/correctivas).
    this.retirarTareasAgendaScheduler(
      tareasReordenables.map((tarea) => tarea.id),
    );

    const actualizaciones: Array<{
      id: number;
      fechaInicio: Date;
      fechaFin: Date;
    }> = [];
    let componentesSinOrdenar = 0;

    for (const tareasDia of porDia.values()) {
      const fecha = tareasDia[0].fechaInicio;

      const pendientes = new Set(tareasDia.map((tarea) => tarea.id));
      while (pendientes.size) {
        const primerId = pendientes.values().next().value as number;
        const componenteIds = new Set<number>([primerId]);
        const operariosComponente = new Set<string>(
          tareasDia
            .find((tarea) => tarea.id === primerId)!
            .operarios.map((operario) => operario.id),
        );
        let crecio = true;
        while (crecio) {
          crecio = false;
          for (const tarea of tareasDia) {
            if (!pendientes.has(tarea.id) || componenteIds.has(tarea.id)) {
              continue;
            }
            if (
              tarea.operarios.length > 0 &&
              tarea.operarios.some((operario) =>
                operariosComponente.has(operario.id),
              )
            ) {
              componenteIds.add(tarea.id);
              tarea.operarios.forEach((operario) =>
                operariosComponente.add(operario.id),
              );
              crecio = true;
            }
          }
        }
        componenteIds.forEach((id) => pendientes.delete(id));
        const componente = tareasDia.filter((tarea) =>
          componenteIds.has(tarea.id),
        );

        // Ventana de ESTE componente (los operarios que comparte): la de su
        // plaza si tiene horario especial, o el horario general del
        // conjunto en cualquier otro caso -igual que en la generación
        // inicial-. Antes se usaba un único horario por día para todo el
        // conjunto, así que una tarea de una plaza con horario especial
        // (p.ej. 09:00-20:00) que caía el mismo día de la semana en que el
        // conjunto SÍ tiene fila general (p.ej. 07:00-17:00) terminaba
        // reposicionada aquí dentro del horario general, fuera del horario
        // real de su plaza.
        const horariosComponente = await this.horariosPorDiaParaOperarios(
          params.conjuntoId,
          [...operariosComponente],
        );
        const festivoHorarioComponente = await this.festivoHorarioParaOperarios(
          params.conjuntoId,
          [...operariosComponente],
        );
        const horario = resolverHorarioConFestivo(
          fecha,
          horariosComponente,
          festivosSetReorden,
          festivoHorarioComponente,
        );
        if (!horario) {
          componentesSinOrdenar++;
          this.retirarTareasAgendaScheduler(
            componente.map((tarea) => tarea.id),
          );
          for (const tarea of componente) {
            this.registrarIntervaloAgendaScheduler({
              tareaId: tarea.id,
              fechaInicio: tarea.fechaInicio,
              fechaFin: tarea.fechaFin,
              operariosIds: tarea.operarios.map((operario) => operario.id),
              borrador: true,
            });
          }
          continue;
        }

        type PropuestaZona = {
          tarea: (typeof tareas)[number];
          fechaInicio: Date;
          fechaFin: Date;
        };
        let propuestas: PropuestaZona[] | null = null;

        // Primero el orden completo (categoria -> orden interno -> prioridad
        // -> definicion). Si la sincronizacion concreta del dia no encaja, se
        // reintenta conservando solo el orden de categorias y el horario
        // previo dentro de cada una.
        for (const estricto of [true, false]) {
          this.retirarTareasAgendaScheduler(
            componente.map((tarea) => tarea.id),
          );
          const ordenadas = ordenarPorProgramacion(componente, (tarea) =>
            datosOrden(tarea, estricto),
          );
          const intento: PropuestaZona[] = [];
          let valido = true;

          for (const tarea of ordenadas) {
            const operariosIds = tarea.operarios.map((operario) => operario.id);
            const bloqueos = [
              ...buildBloqueosPorDescanso(horario),
              ...(await this.bloqueosPatronScheduler({
                conjuntoId: params.conjuntoId,
                fecha,
                horario,
                operariosIds,
              })),
            ];
            const ocupados = this.ocupadosAgendaScheduler({
              fecha,
              operariosIds,
              incluirPublicadas: true,
              bloqueos,
            });
            const duracion = Math.max(1, tarea.duracionMinutos);
            const bloque = buscarHuecoDiaConSplitEarliest({
              startMin: horario.startMin,
              endMin: horario.endMin,
              durMin: duracion,
              ocupados,
              bloqueos,
              desiredStartMin: horario.startMin,
              maxBloques: 1,
            })?.[0];
            if (!bloque || bloque.f - bloque.i !== duracion) {
              valido = false;
              break;
            }
            const fechaInicio = toDateAtMin(fecha, bloque.i);
            const fechaFin = toDateAtMin(fecha, bloque.f);
            intento.push({ tarea, fechaInicio, fechaFin });
            this.registrarIntervaloAgendaScheduler({
              tareaId: tarea.id,
              fechaInicio,
              fechaFin,
              operariosIds,
              borrador: true,
            });
          }

          if (valido) {
            propuestas = intento;
            break;
          }
        }

        if (!propuestas) {
          componentesSinOrdenar++;
          this.retirarTareasAgendaScheduler(
            componente.map((tarea) => tarea.id),
          );
          for (const tarea of componente) {
            this.registrarIntervaloAgendaScheduler({
              tareaId: tarea.id,
              fechaInicio: tarea.fechaInicio,
              fechaFin: tarea.fechaFin,
              operariosIds: tarea.operarios.map((operario) => operario.id),
              borrador: true,
            });
          }
          continue;
        }

        for (const propuesta of propuestas) {
          if (
            +propuesta.tarea.fechaInicio !== +propuesta.fechaInicio ||
            +propuesta.tarea.fechaFin !== +propuesta.fechaFin
          ) {
            actualizaciones.push({
              id: propuesta.tarea.id,
              fechaInicio: propuesta.fechaInicio,
              fechaFin: propuesta.fechaFin,
            });
          }
        }
      }
    }

    const aplicar = async (db: Pick<Prisma.TransactionClient, "tarea">) => {
      for (const item of actualizaciones) {
        await db.tarea.update({
          where: { id: item.id },
          data: {
            fechaInicio: item.fechaInicio,
            fechaFin: item.fechaFin,
          },
        });
      }
    };
    const transaccion = (this.prisma as any).$transaction;
    if (actualizaciones.length && typeof transaccion === "function") {
      await this.prisma.$transaction(async (tx) => aplicar(tx));
    } else if (actualizaciones.length) {
      await aplicar(this.prisma as any);
    }

    return {
      reordenadas: actualizaciones.length,
      componentesSinOrdenar,
    };
  }

  /**
   * Rescate por capacidades. Una tarea solo debe quedar excluida cuando no
   * existe ningun recurso compatible y disponible. Para cada excluida de ESTA
   * corrida por falta de cupo (SIN_HUECO, SIN_CANDIDATAS, SIN_CAPACIDAD_P1,
   * NECESIDAD_SIN_OPERARIO o desplazada por prioridad) se buscan plazas del
   * mismo conjunto, distintas de la del responsable, cuyo PERFIL tenga la
   * categoria de la preventiva entre sus capacidades configuradas (nunca se
   * infiere por el nombre del cargo). La tarea se coloca con los mismos
   * criterios que el rescate mensual del responsable: fecha objetivo, luego
   * dias cercanos y menos cargados, respetando horario de esa plaza,
   * festivos, descanso compensatorio, disponibilidad, solapes, tope semanal y
   * la regla de no repetir la misma tarea el mismo dia.
   *
   * Solo puede reducir las excluidas: lo que no encuentra recurso queda como
   * estaba. No aplica a cuadrillas (varios responsables), a tareas de varios
   * dias ni a definiciones sin categoria activa.
   */
  private async rescatarExcluidasPorCapacidad(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    defsPorId: Map<number, any>;
    festivosSet: Set<string>;
    incluirPublicadasEnAgenda: boolean;
    novedades: NovedadCronograma[];
  }): Promise<{ reasignadas: number; tareasCreadas: number; sinRecursoCompatible: number }> {
    const resultado = { reasignadas: 0, tareasCreadas: 0, sinRecursoCompatible: 0 };
    const { conjuntoId, periodoAnio, periodoMes } = params;

    const excluidas = this.excluidasDeLaCorrida.filter(
      (e) =>
        e.conjuntoId === conjuntoId &&
        e.periodoAnio === periodoAnio &&
        e.periodoMes === periodoMes &&
        e.estado === "PENDIENTE" &&
        e.defId != null &&
        motivoRescatablePorCapacidad(e.motivoTipo),
    );
    if (!excluidas.length) return resultado;

    const plazasDb = await this.prisma.conjuntoNecesidadOperario.findMany({
      where: { conjuntoId, activo: true },
      include: {
        perfil: {
          select: { activo: true, categorias: { select: { categoriaId: true } } },
        },
        operario: { select: { id: true, usuario: { select: { nombre: true } } } },
      },
    });
    const plazas: PlazaRecurso[] = plazasDb.map((p) => ({
      id: p.id,
      orden: p.orden,
      operarioId: p.operarioId,
      plazaActiva: p.activo,
      perfilActivo: p.perfil?.activo ?? false,
      categoriasPermitidas: new Set(p.perfil?.categorias.map((c) => c.categoriaId) ?? []),
    }));
    // Sin capacidades configuradas no hay a quien reasignar: el generador se
    // comporta exactamente como antes.
    if (!plazas.some((p) => p.operarioId != null && p.categoriasPermitidas.size > 0)) {
      return resultado;
    }
    const plazaPorId = new Map(plazasDb.map((p) => [p.id, p]));

    const categoriasIds = Array.from(
      new Set(
        excluidas
          .map((e) => params.defsPorId.get(e.defId as number)?.categoriaId)
          .filter((id): id is number => id != null),
      ),
    );
    if (!categoriasIds.length) return resultado;
    const categorias = new Map(
      (
        await this.prisma.categoriaTarea.findMany({
          where: { id: { in: categoriasIds } },
          select: { id: true, ordenProgramacion: true, activa: true },
        })
      ).map((c) => [c.id, c]),
    );

    const items = excluidas.flatMap((excluida) => {
      const def = params.defsPorId.get(excluida.defId as number);
      if (!def || def.categoriaId == null) return [];
      const categoria = categorias.get(def.categoriaId);
      if (!categoria?.activa) return [];
      if (Math.max(1, Math.floor(Number(def.diasParaCompletar ?? 1))) > 1) return [];
      // Un solo responsable (plaza u operario directo): las cuadrillas no se reasignan.
      const cantidadResponsables = def.necesidades?.length || excluida.operariosIds.length;
      if (cantidadResponsables !== 1) return [];
      return [
        {
          id: excluida.id,
          defId: def.id as number,
          prioridad: excluida.prioridad,
          categoriaOrden: categoria.ordenProgramacion as number | null,
          ordenEnCategoria: (def.ordenEnCategoria ?? null) as number | null,
          fechaObjetivoMs: +excluida.fechaObjetivo,
          excluida,
          def,
          categoriaId: categoria.id as number,
        },
      ];
    });
    if (!items.length) return resultado;

    const inicioMes = new Date(periodoAnio, periodoMes - 1, 1);
    const finMes = new Date(periodoAnio, periodoMes, 0, 23, 59, 59, 999);
    const inicioDia = (fecha: Date) =>
      new Date(fecha.getFullYear(), fecha.getMonth(), fecha.getDate()).getTime();

    for (const item of ordenarExcluidasParaRescate(items)) {
      const { excluida, def } = item;
      try {
        const operariosDuenos: string[] = excluida.operariosIds;
        const plazasDuenasIds: number[] = def.necesidades?.length
          ? def.necesidades.map((n: { id: number }) => n.id)
          : plazas
              .filter((p) => p.operarioId != null && operariosDuenos.includes(p.operarioId))
              .map((p) => p.id);
        const alternativas = plazasCandidatas({
          categoriaId: item.categoriaId,
          plazasDuenasIds,
          plazas,
        }).filter((p) => !operariosDuenos.includes(p.operarioId as string));
        if (!alternativas.length) {
          resultado.sinRecursoCompatible++;
          continue;
        }

        const ocurrenciaPlanId =
          excluida.ocurrenciaPlanId ??
          (await this.registrarOcurrenciaEsperada({
            def,
            conjuntoId,
            periodoAnio,
            periodoMes,
            fechaObjetivo: excluida.fechaObjetivo,
            duracionEsperadaMin: excluida.duracionMinutos,
            operariosIds: operariosDuenos,
          }));

        type Opcion = {
          plaza: PlazaRecurso;
          operarioId: string;
          plan: BloqueProgramacion[];
          distancia: number;
        };
        const opciones: Opcion[] = [];
        for (const plaza of alternativas) {
          const altIds = [plaza.operarioId as string];
          const horarios = await this.horariosPorDiaParaOperarios(conjuntoId, altIds);
          const festivoHorario = await this.festivoHorarioParaOperarios(conjuntoId, altIds);
          const diasDescanso = await this.diasDescansoParaOperarios(
            conjuntoId,
            altIds,
            inicioMes,
            finMes,
          );
          const festivosSetPlaza = new Set<string>([
            ...(festivoHorario != null ? [] : params.festivosSet),
            ...diasDescanso,
          ]);
          const dias = await this.diasMesPorAprovechamiento({
            conjuntoId,
            fechaObjetivo: excluida.fechaObjetivo,
            periodoAnio,
            periodoMes,
            operariosIds: altIds,
            horariosPorDia: horarios,
            festivosSet: festivosSetPlaza,
            festivosSetRaw: params.festivosSet,
            festivoHorario,
            definicionId: def.id,
            descripcion: def.descripcion,
            ubicacionId: def.ubicacionId,
            elementoId: def.elementoId,
          });
          if (!dias.length) continue;
          const plan = await this.construirMejorPlanEnDias({
            conjuntoId,
            duracionMinutos: excluida.duracionMinutos,
            operariosIds: altIds,
            dias,
            horariosPorDia: horarios,
            festivosSet: festivosSetPlaza,
            festivosSetRaw: params.festivosSet,
            festivoHorario,
            incluirPublicadasEnAgenda: params.incluirPublicadasEnAgenda,
          });
          if (!plan.length) continue;
          opciones.push({
            plaza,
            operarioId: altIds[0],
            plan,
            distancia: Math.abs(
              inicioDia(plan[0].fechaInicio) - inicioDia(excluida.fechaObjetivo),
            ),
          });
        }
        if (!opciones.length) {
          resultado.sinRecursoCompatible++;
          continue;
        }

        // Mas cercana a la fecha objetivo, luego menos fragmentos, luego la
        // plaza menos cargada ese dia, luego orden e id de plaza (determinista).
        const minDistancia = Math.min(...opciones.map((o) => o.distancia));
        let finalistas = opciones.filter((o) => o.distancia === minDistancia);
        const minBloques = Math.min(...finalistas.map((o) => o.plan.length));
        finalistas = finalistas.filter((o) => o.plan.length === minBloques);
        let elegida = finalistas[0];
        if (finalistas.length > 1) {
          const cargas = new Map<number, number>();
          for (const f of finalistas) {
            const cargaDia = await this.cargaOperariosEnDias({
              conjuntoId,
              dias: [f.plan[0].fechaInicio],
              operariosIds: [f.operarioId],
              horariosPorDia: await this.horariosPorDiaParaOperarios(conjuntoId, [f.operarioId]),
            });
            cargas.set(f.plaza.id, cargaDia.get(dayKey(f.plan[0].fechaInicio)) ?? 0);
          }
          const primera = ordenarCandidatasPorCarga(
            finalistas.map((f) => f.plaza),
            (id) => cargas.get(id) ?? 0,
          )[0];
          elegida = finalistas.find((f) => f.plaza.id === primera.id) as Opcion;
        }

        const plazaElegida = plazaPorId.get(elegida.plaza.id);
        const nuevaTareaIds = await this.crearBloquesPreventivosDeDefinicion({
          def,
          conjuntoId,
          periodoAnio,
          periodoMes,
          ocurrenciaPlanId,
          prioridad: Number(excluida.prioridad),
          operariosIds: [elegida.operarioId],
          bloques: elegida.plan,
          grupoPlanId: null,
          bloqueIndexBase: 1,
          bloquesTotales: elegida.plan.length,
          reasignacion: {
            necesidadId: elegida.plaza.id,
            necesidadPrevistaId: plazasDuenasIds[0] ?? null,
          },
        });

        const fechaNueva = dayKey(elegida.plan[0].fechaInicio);
        const fechaObjetivo = dayKey(excluida.fechaObjetivo);
        const nombreOperario =
          plazaElegida?.operario?.usuario?.nombre ?? elegida.operarioId;
        const etiqueta = plazaElegida?.etiqueta ?? `plaza ${elegida.plaza.id}`;
        const mensaje =
          `'${def.descripcion}' no tenia espacio con su responsable; la ejecuta ${nombreOperario} (${etiqueta}), ` +
          `cuyo perfil esta habilitado para esa categoria, el ${fechaNueva}.`;

        await this.prisma.preventivaExcluidaBorrador.update({
          where: { id: excluida.id },
          data: {
            estado: "AGENDADA",
            tareaProgramadaId: nuevaTareaIds[0] ?? null,
            resueltaEn: new Date(),
            metadataJson: {
              ...this.metadataAsObject(excluida.metadataJson),
              reasignacionAutomatica: {
                desdeNecesidadId: plazasDuenasIds[0] ?? null,
                haciaNecesidadId: elegida.plaza.id,
                haciaOperarioId: elegida.operarioId,
              },
            } as Prisma.InputJsonValue,
          },
        });
        await this.registrarEventoBorrador({
          conjuntoId,
          periodoAnio,
          periodoMes,
          tipo: "REASIGNADA_POR_CAPACIDAD",
          accionAuditoria: AccionAuditoria.REASIGNAR_OPERARIO,
          origenAuditoria: OrigenAuditoria.SCHEDULER,
          detalle: mensaje,
          excluidaId: excluida.id,
          tareaId: nuevaTareaIds[0] ?? null,
          metadataJson: {
            defId: def.id,
            fechaObjetivo,
            fechaNueva,
            desdeNecesidadId: plazasDuenasIds[0] ?? null,
            haciaNecesidadId: elegida.plaza.id,
            haciaOperarioId: elegida.operarioId,
            nuevaTareaIds,
          },
        });

        // La novedad de "sin espacio" de esa ocurrencia ya no aplica.
        const idx = params.novedades.findIndex(
          (n) =>
            (n.tipo === "SIN_HUECO" || n.tipo === "SIN_CANDIDATAS") &&
            n.defId === def.id &&
            n.fecha === fechaObjetivo,
        );
        if (idx >= 0) params.novedades.splice(idx, 1);
        params.novedades.push({
          tipo: "REASIGNADA_POR_CAPACIDAD",
          defId: def.id,
          descripcion: def.descripcion,
          prioridad: Number(excluida.prioridad),
          fecha: fechaNueva,
          fechaObjetivo,
          nuevaTareaIds,
          desdeNecesidadId: plazasDuenasIds[0] ?? null,
          haciaNecesidadId: elegida.plaza.id,
          haciaEtiqueta: etiqueta,
          haciaOperarioId: elegida.operarioId,
          mensaje,
        });
        resultado.reasignadas++;
        resultado.tareasCreadas += nuevaTareaIds.length;
      } catch (error) {
        // Mejora best-effort: si falla una reasignacion, la excluida queda
        // pendiente como siempre y la generacion continua.
        console.error("[rescate-capacidad] no se pudo reasignar la excluida", excluida.id, error);
      }
    }
    return resultado;
  }

  /** Comprueba que todos los operarios sigan bajo su tope semanal tras sumar `minutosAdicionales`. */
  private async cabeEnLimiteSemanal(params: {
    conjuntoId: string;
    operariosIds: string[];
    fechaReferencia: Date;
    minutosAdicionales: number;
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    incluirPublicadasEnAgenda: boolean;
    cacheLimite?: Map<string, number>;
  }): Promise<boolean> {
    const {
      conjuntoId,
      operariosIds,
      fechaReferencia,
      minutosAdicionales,
      horariosPorDia,
      incluirPublicadasEnAgenda,
      cacheLimite,
    } = params;

    const claveSemana = dayKey(inicioSemana(fechaReferencia));

    for (const operarioId of operariosIds) {
      const clave = `${operarioId}|${claveSemana}`;
      let limite = cacheLimite?.get(clave);
      limite ??= this.limiteSemanalSchedulerCache.get(clave);
      if (limite == null) {
        limite = await getLimiteMinSemanaPorOperario({
          prisma: this.prisma,
          conjuntoId,
          operarioId,
          horariosPorDia: horariosPorDia as any,
          fechaReferencia,
        });
        cacheLimite?.set(clave, limite);
        this.limiteSemanalSchedulerCache.set(clave, limite);
      }

      const claveAsignados = `${operarioId}|${claveSemana}|${incluirPublicadasEnAgenda}`;
      let asignados = this.minutosSemanaSchedulerCache.get(claveAsignados);
      if (asignados == null) {
        asignados = await minutosAsignadosEnSemana(
          this.prisma,
          conjuntoId,
          operarioId,
          fechaReferencia,
          incluirPublicadasEnAgenda,
        );
        this.minutosSemanaSchedulerCache.set(claveAsignados, asignados);
      }

      if (asignados + minutosAdicionales > limite) return false;
    }

    return true;
  }

  private async construirPlanFlexibleExcluida(params: {
    conjuntoId: string;
    excluida: {
      id: number;
      periodoAnio: number;
      periodoMes: number;
      descripcion: string;
      duracionMinutos: number;
      fechaObjetivo: Date;
      operariosIds: string[];
    };
    fechas: Date[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
    preferida: Date;
    startIndex: number;
  }): Promise<BloqueProgramacion[]> {
    const { excluida, fechas, startIndex } = params;
    if (startIndex < 0 || startIndex >= fechas.length) return [];

    const plan = await this.construirPlanEnRango({
      conjuntoId: params.conjuntoId,
      duracionMinutos: excluida.duracionMinutos,
      operariosIds: excluida.operariosIds,
      dias: fechas.slice(startIndex),
      horariosPorDia: params.horariosPorDia,
      festivosSet: params.festivosSet,
      preferida: params.preferida,
      maxBloquesPorDia: 2,
      permitirMultiDia: false,
      splitSoloPorDescanso: true,
    });

    // Esta variante solo aporta valor cuando el plan realmente se divide:
    // el caso de un unico bloque ya lo cubre la busqueda de hueco simple.
    return plan.length > 1 ? plan : [];
  }

  private idOcurrenciaPlan(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    defId: number;
    fechaObjetivo: Date;
  }) {
    return [
      "preventiva",
      params.conjuntoId,
      `${params.periodoAnio}-${String(params.periodoMes).padStart(2, "0")}`,
      params.defId,
      dayKey(params.fechaObjetivo),
      this.ocurrenciaPlanRunId,
    ].join(":");
  }

  private async registrarOcurrenciaEsperada(params: {
    def: any;
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    fechaObjetivo: Date;
    duracionEsperadaMin: number;
    operariosIds: string[];
  }) {
    const id = this.idOcurrenciaPlan({
      conjuntoId: params.conjuntoId,
      periodoAnio: params.periodoAnio,
      periodoMes: params.periodoMes,
      defId: params.def.id,
      fechaObjetivo: params.fechaObjetivo,
    });
    const repo = (this.prisma as any).preventivaOcurrenciaPlan;
    if (!repo?.upsert) return id;

    const operariosNombres = (params.def.operarios ?? [])
      .map((operario: any) => operario.usuario?.nombre ?? "")
      .filter((nombre: string) => nombre.length > 0);
    const snapshot = {
      conjuntoId: params.conjuntoId,
      periodoAnio: params.periodoAnio,
      periodoMes: params.periodoMes,
      borrador: true,
      defId: params.def.id,
      descripcion: params.def.descripcion,
      frecuencia: params.def.frecuencia ?? null,
      prioridad: Number(params.def.prioridad ?? 2),
      fechaObjetivo: params.fechaObjetivo,
      duracionEsperadaMin: Math.max(1, params.duracionEsperadaMin),
      ubicacionId: params.def.ubicacionId,
      ubicacionNombre: params.def.ubicacion?.nombre ?? null,
      elementoId: params.def.elementoId,
      elementoNombre:
        construirRutaElemento(params.def.elemento as any) ?? null,
      operariosEsperadosIds: params.operariosIds,
      operariosEsperadosNombres: operariosNombres,
    };
    await repo.upsert({
      where: { id },
      create: { id, ...snapshot },
      update: snapshot,
    });
    return id;
  }

  private async reconciliarOcurrenciaProgramada(ocurrenciaPlanId: string) {
    const repo = (this.prisma as any).preventivaOcurrenciaPlan;
    if (!repo?.findUnique || !repo?.update) return;
    const ocurrencia = await repo.findUnique({
      where: { id: ocurrenciaPlanId },
      select: { duracionEsperadaMin: true, fechaObjetivo: true },
    });
    if (!ocurrencia) return;
    const tareas = await this.prisma.tarea.findMany({
      where: {
        ocurrenciaPlanId,
        estado: { not: EstadoTarea.PENDIENTE_REPROGRAMACION },
      },
      select: { fechaInicio: true, fechaFin: true, duracionMinutos: true },
      orderBy: { fechaInicio: "asc" },
    });
    const minutos = tareas.reduce(
      (total, tarea) => total + Math.max(0, tarea.duracionMinutos),
      0,
    );
    const fechaRealInicio = tareas[0]?.fechaInicio ?? null;
    const fechaRealFin = tareas.reduce<Date | null>(
      (maxima, tarea) =>
        maxima == null || tarea.fechaFin > maxima ? tarea.fechaFin : maxima,
      null,
    );
    const reubicada =
      fechaRealInicio != null &&
      dayKey(fechaRealInicio) !== dayKey(ocurrencia.fechaObjetivo);
    await repo.update({
      where: { id: ocurrenciaPlanId },
      data: {
        estado:
          minutos <= 0
            ? "SIN_PROGRAMAR"
            : minutos < ocurrencia.duracionEsperadaMin
              ? "PARCIAL"
              : "PROGRAMADA",
        motivoCodigo: reubicada ? "REUBICADA_EN_PERIODO" : null,
        motivoMensaje: reubicada
          ? `Fecha objetivo ${dayKey(ocurrencia.fechaObjetivo)}; programada desde ${dayKey(fechaRealInicio!)}.`
          : null,
        fechaRealInicio,
        fechaRealFin,
      },
    });
  }

  /** Crea las tareas borrador de una definicion preventiva a partir de un plan de bloques. */
  private async crearBloquesPreventivosDeDefinicion(params: {
    def: any;
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    prioridad: number;
    operariosIds: string[];
    bloques: BloqueProgramacion[];
    grupoPlanId: string | null;
    bloqueIndexBase: number;
    bloquesTotales: number;
    ocurrenciaPlanId: string;
    /** Reasignacion automatica por capacidades: plaza que ejecuta y plaza prevista. */
    reasignacion?: { necesidadId: number; necesidadPrevistaId: number | null };
  }): Promise<number[]> {
    const {
      def,
      conjuntoId,
      periodoAnio,
      periodoMes,
      prioridad,
      operariosIds,
      bloques,
      grupoPlanId,
      bloqueIndexBase,
      bloquesTotales,
      ocurrenciaPlanId,
      reasignacion,
    } = params;

    const grupoPlanEfectivo =
      grupoPlanId ??
      (bloques.length > 1
        ? `BOR-${def.id}-${periodoAnio}-${periodoMes}-${randomUUID()}`
        : null);
    const bloquesTotalesEfectivos = grupoPlanEfectivo
      ? grupoPlanId
        ? Math.max(
            bloquesTotales,
            bloqueIndexBase + bloques.length - 1,
          )
        : bloques.length
      : null;

    if (
      grupoPlanId &&
      bloquesTotalesEfectivos != null &&
      bloquesTotalesEfectivos > bloquesTotales
    ) {
      await this.prisma.tarea.updateMany({
        where: { grupoPlanId },
        data: { bloquesTotales: bloquesTotalesEfectivos },
      });
    }

    const ids: number[] = [];
    let indice = bloqueIndexBase;

    for (const bloque of bloques) {
      const creada = await this.prisma.tarea.create({
        data: {
          descripcion: def.descripcion,
          fechaInicio: bloque.fechaInicio,
          fechaFin: bloque.fechaFin,
          duracionMinutos: Math.max(
            1,
            Math.round((bloque.fechaFin.getTime() - bloque.fechaInicio.getTime()) / 60000),
          ),

          tipo: TipoTarea.PREVENTIVA,
          prioridad,
          estado: EstadoTarea.ASIGNADA,
          frecuencia: def.frecuencia,
          definicionId: def.id,
          ocurrenciaPlanId,
          diaSemanaProgramado: def.diaSemanaProgramado ?? null,

          borrador: true,
          periodoAnio,
          periodoMes,

          grupoPlanId: grupoPlanEfectivo,
          bloqueIndex: grupoPlanEfectivo ? indice : null,
          bloquesTotales: bloquesTotalesEfectivos,

          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
          conjuntoId,

          supervisorId: def.supervisorId ?? null,

          // Snapshot de la prioridad de programacion de la definicion.
          categoriaId: def.categoriaId ?? null,
          ordenEnCategoria: def.ordenEnCategoria ?? null,
          reasignadaAutomaticamente: reasignacion != null,
          necesidadPrevistaId: reasignacion?.necesidadPrevistaId ?? null,

          insumosPlanJson: def.insumosPlanJson
            ? (def.insumosPlanJson as Prisma.InputJsonValue)
            : undefined,
          maquinariaPlanJson: def.maquinariaPlanJson
            ? (def.maquinariaPlanJson as Prisma.InputJsonValue)
            : undefined,
          herramientasPlanJson: def.herramientasPlanJson
            ? (def.herramientasPlanJson as Prisma.InputJsonValue)
            : undefined,

          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
          // Vínculo durable a la(s) plaza(s) de origen (si la definición
          // resolvió por necesidad): permite que reasignar el titular de la
          // plaza no requiera editar esta tarea ya creada. En una
          // reasignacion automatica se vincula la plaza que ejecuta.
          necesidades: reasignacion
            ? { connect: [{ id: reasignacion.necesidadId }] }
            : def.necesidades?.length
              ? { connect: def.necesidades.map((n: { id: number }) => ({ id: n.id })) }
              : undefined,
        },
        select: { id: true },
      });

      ids.push(creada.id);
      this.registrarIntervaloAgendaScheduler({
        tareaId: creada.id,
        fechaInicio: bloque.fechaInicio,
        fechaFin: bloque.fechaFin,
        operariosIds,
        borrador: true,
      });
      indice++;
    }

    this.registrarBloquesEnCacheSemanal(bloques, operariosIds);
    this.registrarOcurrenciaDefinicionDiaScheduler({
      definicionId: def.id,
      ocurrenciaPlanId,
      bloques,
    });
    await this.reconciliarOcurrenciaProgramada(ocurrenciaPlanId);
    return ids;
  }

  private async materializarExcluidaEnTarea(params: {
    excluidaId: number;
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
  }) {
    const tareas = await this.materializarExcluidaEnBloques({
      excluidaId: params.excluidaId,
      conjuntoId: params.conjuntoId,
      bloques: [{ fechaInicio: params.fechaInicio, fechaFin: params.fechaFin }],
    });
    return tareas[0];
  }

  /**
   * Los planes de insumos/maquinaria/herramientas no viajan en el snapshot de la excluida.
   * Se recuperan de la definicion (o de la tarea de origen) para que la tarea materializada
   * conserve los mismos recursos que habria tenido si el scheduler la hubiera podido ubicar.
   */
  private async cargarPlanesRecursosExcluida(excluida: {
    defId: number | null;
    origenTareaId: number | null;
  }) {
    const vacio = {
      insumosPlanJson: null as Prisma.JsonValue | null,
      maquinariaPlanJson: null as Prisma.JsonValue | null,
      herramientasPlanJson: null as Prisma.JsonValue | null,
    };

    if (excluida.defId != null) {
      const def = await this.prisma.definicionTareaPreventiva.findUnique({
        where: { id: excluida.defId },
        select: {
          insumosPlanJson: true,
          maquinariaPlanJson: true,
          herramientasPlanJson: true,
        },
      });
      if (def) return def;
    }

    if (excluida.origenTareaId != null) {
      const tarea = await this.prisma.tarea.findUnique({
        where: { id: excluida.origenTareaId },
        select: {
          insumosPlanJson: true,
          maquinariaPlanJson: true,
          herramientasPlanJson: true,
        },
      });
      if (tarea) return tarea;
    }

    return vacio;
  }

  private async materializarExcluidaEnBloques(params: {
    excluidaId: number;
    conjuntoId: string;
    bloques: BloqueProgramacion[];
  }) {
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: params.excluidaId },
    });
    if (!excluida || excluida.conjuntoId !== params.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }
    if (excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida ya fue resuelta o agendada.");
    }

    if (!params.bloques.length) {
      throw new Error("Debes indicar al menos un bloque para agendar la excluida.");
    }

    const bloquesOrdenados = [...params.bloques].sort(
      (a, b) => a.fechaInicio.getTime() - b.fechaInicio.getTime(),
    );
    await this.validarDivisionSoloPorDescanso({
      conjuntoId: params.conjuntoId,
      bloques: bloquesOrdenados,
    });

    const duracionTotal = bloquesOrdenados.reduce(
      (acc, bloque) =>
        acc + Math.max(1, Math.round((bloque.fechaFin.getTime() - bloque.fechaInicio.getTime()) / 60000)),
      0,
    );
    if (duracionTotal !== excluida.duracionMinutos) {
      throw new Error("La suma de bloques no coincide con la duración de la tarea excluida.");
    }

    for (const bloque of bloquesOrdenados) {
      await this.validarSlotPreventivaBorrador({
        conjuntoId: params.conjuntoId,
        fechaInicio: bloque.fechaInicio,
        fechaFin: bloque.fechaFin,
        operariosIds: excluida.operariosIds,
        identidad: this.identidadDeExcluida(excluida),
      });
    }

    const grupoPlanId = bloquesOrdenados.length > 1
      ? `EXC-${excluida.id}-${Date.now().toString(36)}`
      : null;

    const planes = await this.cargarPlanesRecursosExcluida(excluida);
    const necesidadesIds = await this.necesidadesIdsDeDefId(excluida.defId);

    const created = await this.prisma.$transaction(async (tx) => {
      const creadas = [] as Awaited<ReturnType<typeof tx.tarea.create>>[];

      for (let index = 0; index < bloquesOrdenados.length; index++) {
        const bloque = bloquesOrdenados[index];
        const tarea = await tx.tarea.create({
          data: {
            descripcion: excluida.descripcion,
            fechaInicio: bloque.fechaInicio,
            fechaFin: bloque.fechaFin,
            duracionMinutos: Math.max(
              1,
              Math.round((bloque.fechaFin.getTime() - bloque.fechaInicio.getTime()) / 60000),
            ),
            prioridad: excluida.prioridad,
            estado: EstadoTarea.ASIGNADA,
            tipo: TipoTarea.PREVENTIVA,
            frecuencia: excluida.frecuencia,
            definicionId: excluida.defId,
            ocurrenciaPlanId: excluida.ocurrenciaPlanId,
            diaSemanaProgramado: excluida.diaSemanaProgramado,
            borrador: true,
            periodoAnio: excluida.periodoAnio,
            periodoMes: excluida.periodoMes,
            grupoPlanId,
            bloqueIndex: grupoPlanId ? index + 1 : null,
            bloquesTotales: grupoPlanId ? bloquesOrdenados.length : null,
            ubicacionId: excluida.ubicacionId,
            elementoId: excluida.elementoId,
            conjuntoId: params.conjuntoId,
            supervisorId: excluida.supervisorId,
            insumosPlanJson: (planes.insumosPlanJson ?? undefined) as
              | Prisma.InputJsonValue
              | undefined,
            maquinariaPlanJson: (planes.maquinariaPlanJson ?? undefined) as
              | Prisma.InputJsonValue
              | undefined,
            herramientasPlanJson: (planes.herramientasPlanJson ?? undefined) as
              | Prisma.InputJsonValue
              | undefined,
            operarios: excluida.operariosIds.length
              ? { connect: excluida.operariosIds.map((id) => ({ id })) }
              : undefined,
            // Conserva el vínculo a la(s) plaza(s) de origen (si la
            // definición resolvía por necesidad): sin esto la tarea
            // materializada perdía el distintivo visual de horario especial.
            necesidades: necesidadesIds.length
              ? { connect: necesidadesIds.map((id) => ({ id })) }
              : undefined,
          },
        });
        creadas.push(tarea);
      }

      await tx.preventivaExcluidaBorrador.update({
        where: { id: excluida.id },
        data: {
          estado: "AGENDADA",
          tareaProgramadaId: creadas[0]?.id ?? null,
          resueltaEn: new Date(),
        },
      });

      await tx.preventivaBorradorEvento.create({
        data: {
          conjuntoId: params.conjuntoId,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          tipo: "EXCLUIDA_AGENDADA",
          detalle: `La tarea excluida '${excluida.descripcion}' fue agendada manualmente.`,
          excluidaId: excluida.id,
          tareaId: creadas[0]?.id ?? null,
          actorId: this.actor?.id ?? null,
          actorRol: this.actor?.rol ?? null,
          metadataJson: {
            bloques: bloquesOrdenados.map((bloque) => ({
              fechaInicio: bloque.fechaInicio.toISOString(),
              fechaFin: bloque.fechaFin.toISOString(),
            })),
          },
        },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.EXCLUIDA,
        entidad: EntidadAuditoria.EXCLUIDA_BORRADOR,
        entidadId: excluida.id,
        accion: AccionAuditoria.AGENDAR_EXCLUIDA,
        conjuntoId: params.conjuntoId,
        actor: this.actor,
        descripcion: `La tarea excluida '${excluida.descripcion}' fue agendada en el borrador en ${bloquesOrdenados.length} bloque(s).`,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        metadataJson: {
          tareaIds: creadas.map((tarea) => tarea.id),
          bloques: bloquesOrdenados.map((bloque) => ({
            fechaInicio: bloque.fechaInicio.toISOString(),
            fechaFin: bloque.fechaFin.toISOString(),
          })),
        },
      });

      return creadas;
    });

    if (excluida.ocurrenciaPlanId) {
      await this.reconciliarOcurrenciaProgramada(excluida.ocurrenciaPlanId);
    }

    return created;
  }

  /* =========================
   * CRUD BÁSICO
   * ======================= */

  async crear(payload: unknown) {
    return this.crearConCliente(this.prisma, payload);
  }

  async crearEnTransaccion(
    tx: Prisma.TransactionClient,
    payload: unknown,
  ) {
    return this.crearConCliente(tx, payload);
  }

  /** Confirma que todas las necesidades pertenecen a ese conjunto (tenant scope). */
  private async validarNecesidadesDelConjunto(
    conjuntoId: string,
    necesidadesIds: number[],
  ): Promise<void> {
    if (!necesidadesIds.length) return;
    const encontradas = await this.prisma.conjuntoNecesidadOperario.findMany({
      where: { id: { in: necesidadesIds }, conjuntoId },
      select: { id: true },
    });
    if (encontradas.length !== new Set(necesidadesIds).size) {
      throw new Error("Alguna de las necesidades indicadas no pertenece a este conjunto.");
    }
  }

  /**
   * Si la definición se liga a necesidades (plazas) y su día programado NO
   * cae en ningún día que esas plazas trabajen, la definición nunca podría
   * cumplirse ese día: el generador la reubicaría en silencio dentro del
   * mes (motivo REUBICADA_EN_PERIODO) sin avisar que la causa es una
   * incompatibilidad estructural, no falta de cupo. Se rechaza aquí en vez
   * de dejar que ocurra eso.
   *
   * Solo aplica a SEMANAL/QUINCENAL (día de semana fijo) y a
   * fechasProgramadasJson (fechas concretas, cuyo día de semana ya se
   * conoce). MENSUAL usa día-del-mes, cuyo día de semana varía cada mes, así
   * que no es una incompatibilidad estructural fija y no se valida aquí.
   */
  private async validarCompatibilidadHorarioNecesidades(params: {
    conjuntoId: string;
    necesidadesIds: number[];
    frecuencia: Frecuencia;
    diaSemanaProgramado?: DiaSemana | null;
    fechasProgramadasJson?: string[] | null;
  }): Promise<void> {
    const {
      conjuntoId,
      necesidadesIds,
      frecuencia,
      diaSemanaProgramado,
      fechasProgramadasJson,
    } = params;
    if (!necesidadesIds.length) return;

    const diasRequeridos = new Set<DiaSemana>();
    if (
      (frecuencia === Frecuencia.SEMANAL || frecuencia === Frecuencia.QUINCENAL) &&
      diaSemanaProgramado
    ) {
      diasRequeridos.add(diaSemanaProgramado);
    }
    for (const fecha of fechasProgramadasJson ?? []) {
      diasRequeridos.add(diaSemanaFromDate(new Date(`${fecha}T00:00:00`)));
    }
    if (!diasRequeridos.size) return;

    const necesidades = await this.prisma.conjuntoNecesidadOperario.findMany({
      where: { id: { in: necesidadesIds }, conjuntoId },
      select: {
        etiqueta: true,
        horarioEspecial: true,
        horarios: { select: { dia: true } },
      },
    });

    let horarioGeneralDias: Set<DiaSemana> | null = null;
    const diasCubiertos = new Set<DiaSemana>();
    for (const n of necesidades) {
      if (n.horarioEspecial) {
        for (const h of n.horarios) diasCubiertos.add(h.dia);
        continue;
      }
      if (horarioGeneralDias == null) {
        const filas = await this.prisma.conjuntoHorario.findMany({
          where: { conjuntoId },
          select: { dia: true },
        });
        horarioGeneralDias = new Set(filas.map((f) => f.dia));
      }
      for (const d of horarioGeneralDias) diasCubiertos.add(d);
    }

    const faltantes = [...diasRequeridos].filter((d) => !diasCubiertos.has(d));
    if (faltantes.length) {
      const etiquetas = necesidades.map((n) => n.etiqueta).join(", ");
      throw new Error(
        `El día programado (${faltantes.join(", ")}) está fuera del horario de la(s) plaza(s) asignada(s) (${etiquetas}). Ajusta el día programado o el horario especial de la plaza antes de guardar.`,
      );
    }
  }

  private async crearConCliente(
    client: PrismaClient | Prisma.TransactionClient,
    payload: unknown,
  ) {
    const dto = CrearDefinicionPreventivaDTO.parse(payload);
    this.validarProgramacionFrecuencia(dto);
    if (dto.necesidadesIds?.length) {
      await this.validarNecesidadesDelConjunto(dto.conjuntoId, dto.necesidadesIds);
      await this.validarCompatibilidadHorarioNecesidades({
        conjuntoId: dto.conjuntoId,
        necesidadesIds: dto.necesidadesIds,
        frecuencia: dto.frecuencia,
        diaSemanaProgramado: dto.diaSemanaProgramado,
        fechasProgramadasJson: dto.fechasProgramadasJson,
      });
    }

    if (dto.categoriaId != null) {
      await new CatalogoOperativoService(this.prisma).validarCategoriaDeDefinicion({
        conjuntoId: dto.conjuntoId,
        categoriaId: dto.categoriaId,
        necesidadesIds: dto.necesidadesIds ?? [],
        operariosIds: dto.operariosIds?.length
          ? dto.operariosIds.map(String)
          : dto.responsableSugeridoId != null
            ? [String(dto.responsableSugeridoId)]
            : [],
      });
    }

    const supervisorIdResuelto =
      dto.supervisorId != null
        ? await this.resolverSupervisorId(dto.supervisorId)
        : null;

    const duracionMinutosFija =
      dto.duracionMinutosFija ??
      (dto.duracionHorasFija != null
        ? Math.max(1, Math.round(Number(dto.duracionHorasFija) * 60))
        : null);

    const data: any = {
      conjunto: { connect: { nit: dto.conjuntoId } },
      ubicacion: { connect: { id: dto.ubicacionId } },
      elemento: { connect: { id: dto.elementoId } },

      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad ?? 2,
      categoria:
        dto.categoriaId != null ? { connect: { id: dto.categoriaId } } : undefined,
      // El orden interno solo tiene sentido dentro de una categoría.
      ordenEnCategoria:
        dto.categoriaId != null ? (dto.ordenEnCategoria ?? null) : null,

      diaSemanaProgramado: dto.diaSemanaProgramado ?? null,
      diaMesProgramado: dto.diaMesProgramado ?? null,
      fechasProgramadasJson: dto.fechasProgramadasJson
        ? (dto.fechasProgramadasJson as unknown as Prisma.InputJsonValue)
        : undefined,

      duracionMinutosFija,
      diasParaCompletar: dto.diasParaCompletar ?? null,

      rendimientoTiempoBase: dto.rendimientoTiempoBase ?? "POR_MINUTO",

      unidadCalculo: dto.unidadCalculo ?? null,
      areaNumerica:
        dto.areaNumerica != null ? new Prisma.Decimal(dto.areaNumerica) : null,
      rendimientoBase:
        dto.rendimientoBase != null
          ? new Prisma.Decimal(dto.rendimientoBase)
          : null,

      // Insumo principal
      insumoPrincipal: dto.insumoPrincipalId
        ? { connect: { id: dto.insumoPrincipalId } }
        : undefined,
      consumoPrincipalPorUnidad:
        dto.consumoPrincipalPorUnidad != null
          ? new Prisma.Decimal(dto.consumoPrincipalPorUnidad)
          : null,

      // JSONs
      insumosPlanJson: dto.insumosPlanJson
        ? (dto.insumosPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,
      maquinariaPlanJson: dto.maquinariaPlanJson
        ? (dto.maquinariaPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,
      herramientasPlanJson: dto.herramientasPlanJson
        ? (dto.herramientasPlanJson as unknown as Prisma.InputJsonValue)
        : undefined,

      // supervisor (relación)
      supervisor: supervisorIdResuelto
        ? { connect: { id: supervisorIdResuelto } }
        : undefined,

      activo: dto.activo ?? true,
    };

    // Operarios: operariosIds > responsableSugeridoId (fallback si no hay necesidades)
    if (dto.operariosIds?.length) {
      (data as any).operarios = {
        connect: dto.operariosIds.map((id) => ({ id })),
      };
    } else if (dto.responsableSugeridoId != null) {
      (data as any).operarios = {
        connect: { id: dto.responsableSugeridoId },
      };
    }

    // Necesidad primero: si se vinculan plazas, el generador las prioriza
    // sobre `operarios` (ver operariosIdsDeDefinicion).
    if (dto.necesidadesIds?.length) {
      (data as any).necesidades = {
        connect: dto.necesidadesIds.map((id) => ({ id })),
      };
    }

    return client.definicionTareaPreventiva.create({ data });
  }

  async listar(payload: unknown) {
    const f = FiltroDefinicionPreventivaDTO.parse(payload);
    return this.prisma.definicionTareaPreventiva.findMany({
      where: {
        conjuntoId: f.conjuntoId,
        ubicacionId: f.ubicacionId,
        elementoId: f.elementoId,
        frecuencia: f.frecuencia,
        activo: f.activo,
      },
      include: {
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        categoria: {
          select: { id: true, nombre: true, ordenProgramacion: true, colorHex: true, activa: true },
        },
        // El frontend (DefinicionPreventiva.fromJson) solo lee operarios[].id
        // y el supervisorId plano; no necesita la fila Usuario completa.
        operarios: { select: { id: true } },
        necesidades: {
          select: { id: true, etiqueta: true, roles: true, operarioId: true },
        },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
  }

  async listarPorConjunto(conjuntoId: string) {
    return this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId },
      include: {
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        categoria: {
          select: { id: true, nombre: true, ordenProgramacion: true, colorHex: true, activa: true },
        },
        operarios: { select: { id: true } },
        necesidades: {
          select: { id: true, etiqueta: true, roles: true, operarioId: true },
        },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });
  }

  async actualizar(conjuntoId: string, id: number, payload: unknown) {
    const dto = EditarDefinicionPreventivaDTO.parse(payload);

    const def = await this.prisma.definicionTareaPreventiva.findUnique({
      where: { id },
      select: { id: true, conjuntoId: true },
    });
    if (!def || def.conjuntoId !== conjuntoId) {
      throw new Error("Definición no encontrada para este conjunto.");
    }
    if (dto.necesidadesIds?.length) {
      await this.validarNecesidadesDelConjunto(conjuntoId, dto.necesidadesIds);
    }

    const actual: any = await this.prisma.definicionTareaPreventiva.findUnique({
      where: { id },
      select: {
        frecuencia: true,
        diaSemanaProgramado: true,
        diaMesProgramado: true,
        fechasProgramadasJson: true,
        categoriaId: true,
        necesidades: { select: { id: true } },
        operarios: { select: { id: true } },
      } as any,
    });
    if (!actual) {
      throw new Error("Definición no encontrada para este conjunto.");
    }

    const frecuenciaEfectiva = dto.frecuencia ?? actual.frecuencia;
    const diaSemanaEfectivo =
      dto.diaSemanaProgramado === undefined
        ? actual.diaSemanaProgramado
        : dto.diaSemanaProgramado;
    const fechasEfectivas: string[] | null =
      dto.fechasProgramadasJson === undefined
        ? ((actual.fechasProgramadasJson as string[] | null | undefined) ?? null)
        : dto.fechasProgramadasJson;

    this.validarProgramacionFrecuencia({
      frecuencia: frecuenciaEfectiva,
      diaSemanaProgramado: diaSemanaEfectivo,
      diaMesProgramado:
        dto.diaMesProgramado === undefined ? actual.diaMesProgramado : dto.diaMesProgramado,
      fechasProgramadasJson: fechasEfectivas,
    });

    const necesidadesIdsEfectivas: number[] =
      dto.necesidadesIds === undefined
        ? actual.necesidades.map((n: { id: number }) => n.id)
        : (dto.necesidadesIds ?? []);
    if (necesidadesIdsEfectivas.length) {
      await this.validarCompatibilidadHorarioNecesidades({
        conjuntoId,
        necesidadesIds: necesidadesIdsEfectivas,
        frecuencia: frecuenciaEfectiva,
        diaSemanaProgramado: diaSemanaEfectivo,
        fechasProgramadasJson: fechasEfectivas,
      });
    }

    // Categoría efectiva: se valida (existe, activa si cambió y compatible con
    // los responsables efectivos) cuando cambia la categoría o los responsables.
    const categoriaIdEfectiva: number | null =
      dto.categoriaId === undefined ? (actual.categoriaId ?? null) : dto.categoriaId;
    const categoriaCambio = dto.categoriaId !== undefined && dto.categoriaId !== actual.categoriaId;
    const responsablesCambian =
      dto.necesidadesIds !== undefined ||
      (dto as any).operariosIds !== undefined ||
      (dto as any).responsableSugeridoId !== undefined;
    if (categoriaIdEfectiva != null && (categoriaCambio || responsablesCambian)) {
      const operariosEfectivos: string[] =
        (dto as any).operariosIds !== undefined
          ? ((dto as any).operariosIds ?? []).map(String)
          : (dto as any).responsableSugeridoId !== undefined
            ? (dto as any).responsableSugeridoId != null
              ? [String((dto as any).responsableSugeridoId)]
              : []
            : actual.operarios.map((o: { id: string }) => o.id);
      await new CatalogoOperativoService(this.prisma).validarCategoriaDeDefinicion({
        conjuntoId,
        categoriaId: categoriaIdEfectiva,
        necesidadesIds: necesidadesIdsEfectivas,
        operariosIds: operariosEfectivos,
        exigirActiva: categoriaCambio,
      });
    }

    // recalcular duración si vienen campos
    const durMinFija =
      (dto as any).duracionMinutosFija === undefined &&
      (dto as any).duracionHorasFija === undefined
        ? undefined
        : ((dto as any).duracionMinutosFija ??
          ((dto as any).duracionHorasFija != null
            ? Math.round(Number((dto as any).duracionHorasFija) * 60)
            : null));

    const data: any = {
      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad,
      activo: dto.activo,
      categoria:
        dto.categoriaId === undefined
          ? undefined
          : dto.categoriaId === null
            ? { disconnect: true }
            : { connect: { id: dto.categoriaId } },
      // Sin categoría no hay orden interno; al cambiar de categoría el orden
      // anterior (de otra categoría) ya no aplica salvo que se envíe uno nuevo.
      ordenEnCategoria:
        dto.categoriaId === null
          ? null
          : dto.ordenEnCategoria !== undefined
            ? dto.ordenEnCategoria
            : categoriaCambio
              ? null
              : undefined,

      ubicacion:
        dto.ubicacionId === undefined
          ? undefined
          : { connect: { id: dto.ubicacionId } },
      elemento:
        dto.elementoId === undefined
          ? undefined
          : { connect: { id: dto.elementoId } },

      unidadCalculo: dto.unidadCalculo ?? undefined,
      areaNumerica:
        dto.areaNumerica === undefined
          ? undefined
          : dto.areaNumerica === null
            ? null
            : new Prisma.Decimal(dto.areaNumerica),

      rendimientoBase:
        dto.rendimientoBase === undefined
          ? undefined
          : dto.rendimientoBase === null
            ? null
            : new Prisma.Decimal(dto.rendimientoBase),

      diaSemanaProgramado: (dto as any).diaSemanaProgramado ?? undefined,
      diaMesProgramado: (dto as any).diaMesProgramado ?? undefined,
      fechasProgramadasJson:
        (dto as any).fechasProgramadasJson === undefined
          ? undefined
          : ((dto as any).fechasProgramadasJson as Prisma.InputJsonValue | null),
      duracionMinutosFija: durMinFija,

      diasParaCompletar:
        (dto as any).diasParaCompletar === undefined
          ? undefined
          : ((dto as any).diasParaCompletar ?? null),

      insumoPrincipal:
        dto.insumoPrincipalId === undefined
          ? undefined
          : dto.insumoPrincipalId === null
            ? { disconnect: true }
            : { connect: { id: dto.insumoPrincipalId } },

      consumoPrincipalPorUnidad:
        dto.consumoPrincipalPorUnidad === undefined
          ? undefined
          : dto.consumoPrincipalPorUnidad === null
            ? null
            : new Prisma.Decimal(dto.consumoPrincipalPorUnidad),

      insumosPlanJson:
        dto.insumosPlanJson === undefined
          ? undefined
          : dto.insumosPlanJson === null
            ? Prisma.JsonNull
            : (dto.insumosPlanJson as Prisma.InputJsonValue),

      maquinariaPlanJson:
        dto.maquinariaPlanJson === undefined
          ? undefined
          : dto.maquinariaPlanJson === null
            ? Prisma.JsonNull
            : (dto.maquinariaPlanJson as Prisma.InputJsonValue),

      herramientasPlanJson:
        (dto as any).herramientasPlanJson === undefined
          ? undefined
          : (dto as any).herramientasPlanJson === null
            ? Prisma.JsonNull
            : ((dto as any).herramientasPlanJson as Prisma.InputJsonValue),

      supervisor:
        (dto as any).supervisorId === undefined
          ? undefined
          : (dto as any).supervisorId === null
            ? { disconnect: true }
            : {
                connect: {
                  id: await this.resolverSupervisorId((dto as any).supervisorId),
                },
              },
    };

    // relaciones operarios (fallback si no hay necesidades)
    if ((dto as any).operariosIds !== undefined) {
      const operariosIds: number[] = (dto as any).operariosIds ?? [];
      (data as any).operarios = {
        set: operariosIds.map((id) => ({ id: id.toString() })),
      };
    } else if ((dto as any).responsableSugeridoId !== undefined) {
      const value = (dto as any).responsableSugeridoId;
      (data as any).operarios =
        value === null ? { set: [] } : { set: [{ id: value.toString() }] };
    }

    // relación necesidades: `set` reemplaza el vínculo completo (null/[] lo
    // vacía y hace que la definición vuelva a resolver por `operarios`).
    if (dto.necesidadesIds !== undefined) {
      const necesidadesIds = dto.necesidadesIds ?? [];
      (data as any).necesidades = {
        set: necesidadesIds.map((necId) => ({ id: necId })),
      };
    }

    return this.prisma.definicionTareaPreventiva.update({
      where: { id },
      data,
    });
  }

  async eliminar(conjuntoId: string, id: number) {
    const deleted = await this.prisma.definicionTareaPreventiva.deleteMany({
      where: { id, conjuntoId },
    });
    if (deleted.count === 0) {
      throw new Error("Definición no encontrada para este conjunto.");
    }

    await this.auditoria.registrar({
      modulo: ModuloAuditoria.PREVENTIVA,
      entidad: EntidadAuditoria.DEFINICION_PREVENTIVA,
      entidadId: id,
      accion: AccionAuditoria.ELIMINAR,
      conjuntoId,
      actor: this.actor,
      descripcion: "Se eliminó una definición preventiva.",
    });
  }

  /** Borrado en lote: una sola transacción y una sola recarga en el cliente. */
  async eliminarVarias(conjuntoId: string, payload: unknown) {
    const dto = EliminarPreventivasLoteDTO.parse(payload);
    const ids = Array.from(new Set(dto.ids));

    const existentes = await this.prisma.definicionTareaPreventiva.findMany({
      where: { id: { in: ids }, conjuntoId },
      select: { id: true, descripcion: true },
    });

    if (!existentes.length) {
      throw new Error(
        "Ninguna de las preventivas seleccionadas pertenece a este conjunto.",
      );
    }

    const idsEncontrados = existentes.map((item) => item.id);
    const noEncontradas = ids.filter((id) => !idsEncontrados.includes(id));

    await this.prisma.$transaction(async (tx) => {
      await tx.definicionTareaPreventiva.deleteMany({
        where: { id: { in: idsEncontrados }, conjuntoId },
      });

      await new AuditoriaService(tx).registrarLote(
        existentes.map((item) => ({
          modulo: ModuloAuditoria.PREVENTIVA,
          entidad: EntidadAuditoria.DEFINICION_PREVENTIVA,
          entidadId: item.id,
          accion: AccionAuditoria.ELIMINAR,
          conjuntoId,
          actor: this.actor,
          descripcion: `Se eliminó la preventiva '${item.descripcion}' en un borrado múltiple.`,
        })),
      );
    });

    return {
      ok: true,
      eliminadas: idsEncontrados.length,
      noEncontradas,
    };
  }

  /* =========================
   * GENERACIÓN DE CRONOGRAMA
   * ======================= */

  async generarCronograma(payload: unknown) {
    const dto = GenerarCronogramaDTO.parse(payload);

    const tamanoBloqueMinutos =
      dto.tamanoBloqueMinutos ??
      (dto.tamanoBloqueHoras != null
        ? Math.round(dto.tamanoBloqueHoras * 60)
        : 60);

    const paramsGeneracion = {
      conjuntoId: dto.conjuntoId,
      periodoAnio: dto.anio,
      periodoMes: dto.mes,
      tamanoBloqueMinutos,
      paisFestivos: "CO",
      incluirPublicadasEnAgenda: true,
      confirmacionesReemplazo: dto.confirmacionesReemplazo,
      modo: dto.modo,
    } as const;

    // RESET elimina y reconstruye todo el periodo. Debe ser una sustitución
    // atómica: cualquier error restaura el borrador anterior. El advisory lock
    // evita que dos peticiones del mismo conjunto/mes se intercalen.
    const resultado =
      dto.modo === "RESET"
        ? await this.prisma.$transaction(
            async (tx) => {
              const lockKey = `borrador:${dto.conjuntoId}:${dto.anio}:${dto.mes}`;
              // pg_advisory_xact_lock devuelve `void`. Prisma no puede
              // deserializar ese tipo, por lo que proyectamos el resultado de
              // la llamada como un booleano soportado. El lock sigue siendo
              // transaccional y se libera automáticamente al cerrar `tx`.
              await tx.$queryRaw<Array<{ acquired: boolean }>>`
                SELECT pg_advisory_xact_lock(hashtext(${lockKey})) IS NULL AS acquired
              `;
              const serviceTx = new DefinicionTareaPreventivaService(
                tx as unknown as PrismaClient,
                this.actor,
              );
              return serviceTx.generarBorradorMensual(paramsGeneracion);
            },
            {
              isolationLevel: Prisma.TransactionIsolationLevel.Serializable,
              maxWait: 15_000,
              timeout: 120_000,
            },
          )
        : await this.generarBorradorMensual(paramsGeneracion);

    const { creadas, novedades } = resultado;

    return { creadas, novedades };
  }

  /* =========================
   * TAREAS BORRADOR
   * ======================= */

  async dividirTareaBorrador(payload: unknown) {
    const { conjuntoId, tareaId, bloques } =
      DividirTareaBorradorDTO.parse(payload);

    const original = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { operarios: true, necesidades: { select: { id: true } } },
    });

    if (!original || !original.borrador || original.conjuntoId !== conjuntoId) {
      throw new Error(
        "Tarea no encontrada, no es borrador o no pertenece a este conjunto.",
      );
    }
    if (original.tipo !== TipoTarea.PREVENTIVA) {
      throw new Error("Solo se pueden dividir tareas preventivas en borrador.");
    }

    const necesidadesIds = original.necesidades.map((n) => n.id);
    const originalMin = original.duracionMinutos ?? 0;

    const minutosBloques = bloques.reduce((acc, b) => {
      const diffMin = (+b.fechaFin - +b.fechaInicio) / 60000;
      return acc + diffMin;
    }, 0);

    const minutosBloquesRed = Math.round(minutosBloques);
    if (minutosBloquesRed !== originalMin) {
      throw new Error(
        `La suma de minutos de los bloques (${minutosBloquesRed} min) no coincide con la duración original (${originalMin} min).`,
      );
    }

    const operariosIds = original.operarios.map((o) => o.id);

    for (const bloque of bloques) {
      await this.validarSlotPreventivaBorrador({
        conjuntoId,
        fechaInicio: bloque.fechaInicio,
        fechaFin: bloque.fechaFin,
        operariosIds,
        excluirTareaId: tareaId,
      });
    }

    const limiteMinSemana = await getLimiteMinSemanaPorConjunto(
      this.prisma,
      conjuntoId,
    );

    await this.prisma.$transaction(async (tx) => {
      for (const opId of operariosIds) {
        for (const b of bloques) {
          const minSemana = await minutosAsignadosEnSemana(
            tx as any,
            conjuntoId,
            opId,
            b.fechaInicio,
            false,
          );

          const durBloqueMin = (+b.fechaFin - +b.fechaInicio) / 60000 || 0;

          if (minSemana + durBloqueMin > limiteMinSemana) {
            throw new Error(
              `El operario ${opId} superaría el límite semanal (${limiteMinSemana} min) con este bloque.`,
            );
          }

          const haySolape = await existeSolapeParaOperario(tx as any, {
            conjuntoId,
            operarioId: opId,
            fechaInicio: b.fechaInicio,
            fechaFin: b.fechaFin,
            soloBorrador: true,
            excluirTareaId: tareaId,
          });

          if (haySolape) {
            const nombre = await getOperarioNombre(this.prisma, opId);
            throw new Error(
              `Solape de agenda detectado para el operario ${nombre} en uno de los bloques.`,
            );
          }
        }
      }

      await tx.tarea.delete({ where: { id: tareaId } });

      for (const b of bloques) {
        const duracionMinutos = Math.max(
          1,
          Math.round((+b.fechaFin - +b.fechaInicio) / 60000),
        );

        await tx.tarea.create({
          data: {
            descripcion: original.descripcion,
            fechaInicio: b.fechaInicio,
            fechaFin: b.fechaFin,
            duracionMinutos,
            prioridad: (original as any).prioridad ?? 2,
            estado: original.estado,
            tipo: original.tipo,
            frecuencia: original.frecuencia,
            definicionId: original.definicionId ?? null,
            ocurrenciaPlanId: original.ocurrenciaPlanId ?? null,
            diaSemanaProgramado: original.diaSemanaProgramado ?? null,
            borrador: true,
            periodoAnio: b.fechaInicio.getFullYear(),
            periodoMes: b.fechaInicio.getMonth() + 1,

            conjuntoId: original.conjuntoId!,
            ubicacionId: original.ubicacionId,
            elementoId: original.elementoId,
            supervisorId: original.supervisorId,

            tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
            insumoPrincipalId: original.insumoPrincipalId,
            consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
            consumoTotalEstimado: original.consumoTotalEstimado,

            insumosPlanJson:
              original.insumosPlanJson == null
                ? undefined
                : (original.insumosPlanJson as Prisma.InputJsonValue),

            maquinariaPlanJson:
              original.maquinariaPlanJson == null
                ? undefined
                : (original.maquinariaPlanJson as Prisma.InputJsonValue),

            herramientasPlanJson:
              (original as any).herramientasPlanJson == null
                ? undefined
                : ((original as any)
                    .herramientasPlanJson as Prisma.InputJsonValue),

            grupoPlanId: null,
            bloqueIndex: null,
            bloquesTotales: null,

            operarios: operariosIds.length
              ? { connect: operariosIds.map((id) => ({ id })) }
              : undefined,
            necesidades: necesidadesIds.length
              ? { connect: necesidadesIds.map((id) => ({ id })) }
              : undefined,
          },
        });
      }
    });

    if (original.ocurrenciaPlanId) {
      await this.reconciliarOcurrenciaProgramada(original.ocurrenciaPlanId);
    }

    return { ok: true, bloques: bloques.length };
  }

  async dividirBloqueBorrador(
    conjuntoId: string,
    tareaId: number,
    payload: unknown,
  ) {
    const dto = DividirBloqueDTO.parse(payload);

    if (dto.fechaFin1 < dto.fechaInicio1) {
      throw new Error("fechaFin1 debe ser >= fechaInicio1");
    }
    if (dto.fechaFin2 < dto.fechaInicio2) {
      throw new Error("fechaFin2 debe ser >= fechaInicio2");
    }

    const original = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: {
        operarios: { select: { id: true } },
        necesidades: { select: { id: true } },
      },
    });

    if (
      !original ||
      original.conjuntoId !== conjuntoId ||
      !original.borrador ||
      original.tipo !== TipoTarea.PREVENTIVA
    ) {
      throw new Error("No es un bloque borrador preventivo de este conjunto.");
    }

    const operariosIds = original.operarios.map((o) => o.id);
    const necesidadesIds = original.necesidades.map((n) => n.id);

    await this.validarSlotPreventivaBorrador({
      conjuntoId,
      fechaInicio: dto.fechaInicio1,
      fechaFin: dto.fechaFin1,
      operariosIds,
      excluirTareaId: tareaId,
    });
    await this.validarSlotPreventivaBorrador({
      conjuntoId,
      fechaInicio: dto.fechaInicio2,
      fechaFin: dto.fechaFin2,
      operariosIds,
      excluirTareaId: tareaId,
    });

    const dur1 = Math.max(
      1,
      Math.round((+dto.fechaFin1 - +dto.fechaInicio1) / 60000),
    );
    const dur2 = Math.max(
      1,
      Math.round((+dto.fechaFin2 - +dto.fechaInicio2) / 60000),
    );

    const limiteMinSemana = await getLimiteMinSemanaPorConjunto(
      this.prisma,
      conjuntoId,
    );

    const semanaKey = (d: Date) => inicioSemana(d).toISOString().slice(0, 10);
    const semana1 = semanaKey(dto.fechaInicio1);
    const semana2 = semanaKey(dto.fechaInicio2);

    for (const opId of operariosIds) {
      const extraPorSemana: Record<string, number> = {};
      extraPorSemana[semana1] = (extraPorSemana[semana1] ?? 0) + dur1;
      extraPorSemana[semana2] = (extraPorSemana[semana2] ?? 0) + dur2;

      for (const [sem, extra] of Object.entries(extraPorSemana)) {
        const ini = inicioSemana(new Date(sem));
        const minSemana = await minutosAsignadosEnSemana(
          this.prisma,
          conjuntoId,
          opId,
          ini,
          false,
        );

        if (minSemana + extra > limiteMinSemana) {
          throw new Error(
            `Al dividir esta tarea, el operario ${opId} superaría el límite semanal (${limiteMinSemana} min).`,
          );
        }
      }
    }

    for (const opId of operariosIds) {
      const haySolape1 = await existeSolapeParaOperario(this.prisma, {
        conjuntoId,
        operarioId: opId,
        fechaInicio: dto.fechaInicio1,
        fechaFin: dto.fechaFin1,
        soloBorrador: true,
        excluirTareaId: tareaId,
      });

      if (haySolape1) {
        const nombre = await getOperarioNombre(this.prisma, opId);
        throw new Error(
          `Solape de agenda con operario ${nombre} (primer bloque).`,
        );
      }

      const haySolape2 = await existeSolapeParaOperario(this.prisma, {
        conjuntoId,
        operarioId: opId,
        fechaInicio: dto.fechaInicio2,
        fechaFin: dto.fechaFin2,
        soloBorrador: true,
        excluirTareaId: tareaId,
      });

      if (haySolape2) {
        const nombre = await getOperarioNombre(this.prisma, opId);
        throw new Error(
          `Solape de agenda con operario ${nombre} (segundo bloque).`,
        );
      }
    }

    const resultado = await this.prisma.$transaction(async (tx) => {
      await tx.tarea.delete({ where: { id: tareaId } });

      const base: any = {
        descripcion: original.descripcion,
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: original.frecuencia,
        definicionId: original.definicionId ?? null,
        ocurrenciaPlanId: original.ocurrenciaPlanId ?? null,
        diaSemanaProgramado: original.diaSemanaProgramado ?? null,
        borrador: true as const,
        prioridad: (original as any).prioridad ?? 2,

        conjuntoId,
        ubicacionId: original.ubicacionId,
        elementoId: original.elementoId,
        supervisorId: original.supervisorId,

        tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
        insumoPrincipalId: original.insumoPrincipalId,
        consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
        consumoTotalEstimado: original.consumoTotalEstimado,

        insumosPlanJson: original.insumosPlanJson as Prisma.InputJsonValue,
        maquinariaPlanJson:
          original.maquinariaPlanJson as Prisma.InputJsonValue,
        herramientasPlanJson: (original as any)
          .herramientasPlanJson as Prisma.InputJsonValue,

        // Conserva el vínculo a la(s) plaza(s) de origen en ambas mitades:
        // sin esto se perdía el distintivo visual de horario especial al
        // dividir un bloque.
        necesidades: necesidadesIds.length
          ? { connect: necesidadesIds.map((id) => ({ id })) }
          : undefined,
      };

      const tarea1 = await tx.tarea.create({
        data: {
          ...base,
          fechaInicio: dto.fechaInicio1,
          fechaFin: dto.fechaFin1,
          duracionMinutos: dur1,
          periodoAnio: dto.fechaInicio1.getFullYear(),
          periodoMes: dto.fechaInicio1.getMonth() + 1,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      const tarea2 = await tx.tarea.create({
        data: {
          ...base,
          fechaInicio: dto.fechaInicio2,
          fechaFin: dto.fechaFin2,
          duracionMinutos: dur2,
          periodoAnio: dto.fechaInicio2.getFullYear(),
          periodoMes: dto.fechaInicio2.getMonth() + 1,
          grupoPlanId: null,
          bloqueIndex: null,
          bloquesTotales: null,
          operarios: operariosIds.length
            ? { connect: operariosIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      return { tarea1, tarea2 };
    });
    if (original.ocurrenciaPlanId) {
      await this.reconciliarOcurrenciaProgramada(original.ocurrenciaPlanId);
    }
    return resultado;
  }

  async publicarCronograma(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;

    await this.limpiarExcluidasDeMesesAnteriores({ conjuntoId, anio, mes });

    this.validarVentanaPublicacion({ anio, mes, diasAnticipacion: 7 });

    const borradores = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      select: {
        id: true,
        fechaInicio: true,
        fechaFin: true,
        maquinariaPlanJson: true,
        grupoPlanId: true,
        descripcion: true,
      },
      orderBy: [{ id: "asc" }],
    });

    if (!borradores.length) {
      await (this.prisma as any).preventivaOcurrenciaPlan?.updateMany({
        where: {
          conjuntoId,
          periodoAnio: anio,
          periodoMes: mes,
          borrador: true,
        },
        data: { borrador: false },
      });
      return { ok: true, publicadas: 0, reservas: 0 };
    }

    // Publicar solo materializa las tareas y sus necesidades por tipo. La
    // maquina concreta se reserva despues desde el cronograma de maquinaria,
    // donde se valida disponibilidad entre todos los conjuntos de la empresa.

    await this.prisma.tarea.updateMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      data: { borrador: false },
    });
    await (this.prisma as any).preventivaOcurrenciaPlan?.updateMany({
      where: {
        conjuntoId,
        periodoAnio: anio,
        periodoMes: mes,
        borrador: true,
      },
      data: { borrador: false },
    });

    await this.auditoria.registrar({
      modulo: ModuloAuditoria.CRONOGRAMA,
      entidad: EntidadAuditoria.CRONOGRAMA_PERIODO,
      entidadId: `${conjuntoId}-${anio}-${mes}`,
      accion: AccionAuditoria.PUBLICAR,
      conjuntoId,
      actor: this.actor,
      descripcion: `Se publico el cronograma preventivo de ${mes}/${anio} con ${borradores.length} tarea(s).`,
      periodoAnio: anio,
      periodoMes: mes,
      metadataJson: {
        publicadas: borradores.length,
        reservas: 0,
        tareaIds: borradores.map((tarea: any) => tarea.id),
      },
    });

    return {
      ok: true,
      publicadas: borradores.length,
      reservas: 0,
      excluidasDescartadas: 0,
    };
  }

  /**
   * Genera tareas PREVENTIVAS en modo borrador para un conjunto y mes.
   */
  async generarBorradorMensual(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    tamanoBloqueMinutos?: number;
    paisFestivos?: string;
    incluirPublicadasEnAgenda?: boolean;
    confirmacionesReemplazo?: Array<{
      defId: number;
      fecha: string;
      prioridadSolicitante: number;
      prioridadObjetivo: number;
      aceptar: boolean;
      candidataId?: number;
      reprogramarReemplazada?: boolean;
    }>;
    /** CONSERVAR respeta el borrador ya cuadrado y solo planifica lo que falta. */
    modo?: "RESET" | "CONSERVAR";
  }): Promise<{ creadas: number; novedades: NovedadCronograma[] }> {
    const {
      conjuntoId,
      periodoAnio,
      periodoMes,
      tamanoBloqueMinutos = 60,
      paisFestivos = "CO",
      incluirPublicadasEnAgenda = true,
      modo = "RESET",
    } = params;

    // La disponibilidad y los patrones no cambian durante una generación.
    // Se reutilizan entre definiciones y se limpian al iniciar cada corrida.
    this.disponibilidadSchedulerCache.clear();
    this.bloqueosPatronSchedulerCache.clear();
    this.limiteSemanalSchedulerCache.clear();
    this.minutosSemanaSchedulerCache.clear();
    this.horariosPorOperariosCache.clear();
    this.agendaSchedulerActiva = false;
    this.agendaScheduler.clear();
    this.ocurrenciasDefinicionDiaScheduler.clear();
    this.ocurrenciaPlanRunId = randomUUID();

    await this.limpiarExcluidasDeMesesAnteriores({
      conjuntoId,
      anio: periodoAnio,
      mes: periodoMes,
    });

    const novedades: NovedadCronograma[] = [];
    // 1️⃣ Definiciones activas
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, activo: true },
      include: {
        operarios: { include: { usuario: { select: { nombre: true } } } },
        // Necesidad primero, operario como respaldo (ver
        // operariosIdsDeDefinicion): solo se usa si la definición tiene
        // al menos una plaza vinculada.
        necesidades: {
          where: { activo: true },
          include: { operario: { include: { usuario: { select: { nombre: true } } } } },
        },
        supervisor: true,
        ubicacion: { select: { nombre: true } },
        elemento: { include: elementoParentChainInclude },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });

    this.firmaPorDefinicionScheduler.clear();
    for (const def of defs) {
      const firma = firmaTareaPreventiva(def);
      if (firma) this.firmaPorDefinicionScheduler.set(def.id, firma);
    }

    // El orden base conserva P1 > P2 > P3. Más abajo, las P3 se ejecutan en
    // dos fases para que cada definición tenga una primera oportunidad antes
    // de planificar sus repeticiones. Dentro del nivel se priorizan las tareas
    // compartidas, menos flexibles.
    defs.sort((a, b) => {
      const prioridadA = Number((a as any).prioridad ?? 2);
      const prioridadB = Number((b as any).prioridad ?? 2);
      const ordenPrioridad = (prioridad: number) =>
        prioridad === 1 ? 0 : prioridad === 2 ? 1 : 2;
      const ordenA = ordenPrioridad(prioridadA);
      const ordenB = ordenPrioridad(prioridadB);
      if (ordenA !== ordenB) return ordenA - ordenB;
      const operariosA = this.operariosIdsDeDefinicion(a).operariosIds.length;
      const operariosB = this.operariosIdsDeDefinicion(b).operariosIds.length;
      if (operariosA !== operariosB) {
        return operariosB - operariosA;
      }
      return a.id - b.id;
    });

    if (!defs.length) {
      if (modo === "RESET") {
        await this.prisma.tarea.deleteMany({
          where: {
            conjuntoId,
            borrador: true,
            periodoAnio,
            periodoMes,
            tipo: TipoTarea.PREVENTIVA,
          },
        });
        await this.prisma.preventivaExcluidaBorrador.deleteMany({
          where: { conjuntoId, periodoAnio, periodoMes },
        });
        await this.prisma.preventivaBorradorEvento.deleteMany({
          where: { conjuntoId, periodoAnio, periodoMes },
        });
        await (this.prisma as any).preventivaOcurrenciaPlan?.deleteMany({
          where: { conjuntoId, periodoAnio, periodoMes, borrador: true },
        });
      }
      return { creadas: 0, novedades };
    }

    const marcaGeneracionAnterior =
      modo === "CONSERVAR"
        ? await this.prisma.preventivaBorradorEvento.findFirst({
            where: {
              conjuntoId,
              periodoAnio,
              periodoMes,
              tipo: "BORRADOR_GENERADO",
            },
            orderBy: { creadoEn: "desc" },
            select: { metadataJson: true },
          })
        : null;
    const versionesAnteriores = versionesDefinicionesDesdeMetadata(
      marcaGeneracionAnterior?.metadataJson,
    );

    // 2️⃣ Horarios del conjunto
    const horarios = await this.prisma.conjuntoHorario.findMany({
      where: { conjuntoId },
    });

    const horariosPorDia = new Map<
      DiaSemana,
      {
        startMin: number;
        endMin: number;
        descansoStartMin?: number;
        descansoEndMin?: number;
      }
    >();

    for (const h of horarios) {
      horariosPorDia.set(h.dia, {
        startMin: toMin(h.horaApertura),
        endMin: toMin(h.horaCierre),
        descansoStartMin: h.descansoInicio
          ? toMin(h.descansoInicio)
          : undefined,
        descansoEndMin: h.descansoFin ? toMin(h.descansoFin) : undefined,
      });
    }

    // 3️⃣ Rango del mes
    const month0 = periodoMes - 1;
    const inicioMes = new Date(periodoAnio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(periodoAnio, month0 + 1, 0, 23, 59, 59, 999);
    const fechasDelMes = enumerateDays(inicioMes, finMes);

    // 4️⃣ Festivos
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: paisFestivos,
      inicio: inicioMes,
      fin: finMes,
    });

    // Todas las prioridades conservan su fecha contemplada como referencia,
    // aunque sea festivo o no tenga jornada. El rescate posterior recorre los
    // días válidos del mes hacia adelante y hacia atrás. Resolver P3 aquí con
    // `findNextValidDay` hacía que una ocurrencia festiva se descartara antes
    // de llegar a esa búsqueda mensual.
    const resolverDiaObjetivo = (start: Date, _prioridad: number) => {
      if (
        start.getFullYear() !== periodoAnio ||
        start.getMonth() + 1 !== periodoMes
      ) {
        return null;
      }
      return new Date(
        start.getFullYear(),
        start.getMonth(),
        start.getDate(),
        0,
        0,
        0,
        0,
      );
    };

    // 5️⃣ Borrador previo: se descarta solo en modo RESET.
    // En CONSERVAR se respeta lo ya cuadrado a mano y mas abajo se saltan
    // las definiciones que ya tienen tarea o excluida en el periodo.
    const definicionesYaEnBorrador =
      modo === "CONSERVAR"
        ? await this.definicionesConBorrador({ conjuntoId, periodoAnio, periodoMes })
        : null;

    if (modo === "RESET") {
      await this.prisma.tarea.deleteMany({
        where: {
          conjuntoId,
          borrador: true,
          periodoAnio,
          periodoMes,
          tipo: TipoTarea.PREVENTIVA,
        },
      });
      await this.prisma.preventivaExcluidaBorrador.deleteMany({
        where: { conjuntoId, periodoAnio, periodoMes },
      });
      await this.prisma.preventivaBorradorEvento.deleteMany({
        where: { conjuntoId, periodoAnio, periodoMes },
      });
      await (this.prisma as any).preventivaOcurrenciaPlan?.deleteMany({
        where: { conjuntoId, periodoAnio, periodoMes, borrador: true },
      });
    }

    await this.iniciarAgendaScheduler({
      conjuntoId,
      inicio: inicioMes,
      fin: finMes,
    });

    // Solo las excluidas creadas en ESTA corrida son candidatas al rescate por
    // capacidades: se registran en memoria al crearlas (ver crearExcluida).
    this.excluidasDeLaCorrida = [];
    this.rastreoExcluidas = true;

    const publicadasPeriodo = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        periodoAnio,
        periodoMes,
        tipo: TipoTarea.PREVENTIVA,
        borrador: false,
      },
      select: {
        definicionId: true,
        descripcion: true,
        ubicacionId: true,
        elementoId: true,
        frecuencia: true,
      },
    });

    const definicionesPublicadas = new Set(
      publicadasPeriodo
        .map((tarea) => tarea.definicionId)
        .filter((id): id is number => id != null),
    );
    const clavesPublicadas = new Set(
      publicadasPeriodo.map(
        (tarea) =>
          `${tarea.descripcion}|${tarea.ubicacionId}|${tarea.elementoId}|${tarea.frecuencia ?? ""}`,
      ),
    );

    let creadas = 0;

    // 6️⃣ Cola de trabajo. La jerarquía efectiva es:
    //  1) todas las P1 de una jornada, desde las que requieren más fechas;
    //  2) todas las P1 multidía, distribuidas en fechas distintas;
    //  3) primera ocurrencia de cada P2;
    //  4) cobertura mínima de una ocurrencia por cada definición P3;
    //  5) repeticiones de P2 y, al final, repeticiones de P3.
    //
    // La cobertura mínima P3 se intercala únicamente después de que todas las
    // definiciones P2 tuvieron su primera oportunidad. Es la reserva necesaria
    // para que una P2 DIARIA no consuma el mes entero y deje una actividad P3
    // en cero. Fuera de esa garantía, P2 siempre se programa antes que P3.
    // Las rondas también evitan que una P1/P2/P3 corta acapare todos los días
    // antes de que otra definición de la misma prioridad reciba un turno.
    // Dentro de cada ronda la definición de mayor duración entra primero: es
    // la que antes perdía frente a tareas cortas que liberaban su turno rápido.
    const ocurrenciasP3MinimasProtegidas = new Set<string>();
    if (modo === "CONSERVAR") {
      const p3Existentes = await this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          periodoAnio,
          periodoMes,
          borrador: true,
          tipo: TipoTarea.PREVENTIVA,
          prioridad: 3,
          ocurrenciaPlanId: { not: null },
          estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        },
        select: {
          definicionId: true,
          ocurrenciaPlanId: true,
          fechaInicio: true,
        },
        orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
      });
      const definicionesP3Protegidas = new Set<number>();
      for (const tarea of p3Existentes) {
        if (
          tarea.definicionId == null ||
          tarea.ocurrenciaPlanId == null ||
          definicionesP3Protegidas.has(tarea.definicionId)
        ) {
          continue;
        }
        definicionesP3Protegidas.add(tarea.definicionId);
        ocurrenciasP3MinimasProtegidas.add(tarea.ocurrenciaPlanId);
      }
    }

    type InfoDefinicion = {
      def: (typeof defs)[number];
      prioridad: number;
      operariosIds: string[];
      // Ventana de búsqueda resuelta para operariosIds: la(s) plaza(s) de la
      // definición si tienen horario especial, o el horario general del
      // conjunto (idéntico al comportamiento previo) en cualquier otro caso.
      horariosPorDiaDef: Map<DiaSemana, HorarioDia>;
      // Horario festivo envolvente de esos mismos operarios, o null si no
      // pueden trabajar festivos (ver festivoHorarioParaOperarios).
      festivoHorarioDef: HorarioDia | null;
      // Días del mes en que alguno de estos operarios tiene descanso
      // compensatorio (ver diasDescansoParaOperarios): bloquean igual que
      // un festivo no trabajable.
      diasDescansoDef: Set<string>;
      dias: Date[];
      durMin: number;
    };
    type TrabajoOcurrencia = {
      def: (typeof defs)[number];
      prioridad: number;
      operariosIds: string[];
      horariosPorDiaDef: Map<DiaSemana, HorarioDia>;
      festivoHorarioDef: HorarioDia | null;
      diasDescansoDef: Set<string>;
      dia: Date;
      esRondaGarantia: boolean;
    };

    // Los filtros de "ya publicada" / "ya en el borrador" son estáticos (no
    // dependen del día ni de la ronda), así que se evalúan una sola vez aquí
    // en vez de repetirse por cada ocurrencia como antes.
    const defsValidas = defs.filter((def) => {
      const clavePublicada = `${def.descripcion}|${def.ubicacionId}|${def.elementoId}|${def.frecuencia ?? ""}`;
      if (
        definicionesPublicadas.has(def.id) ||
        clavesPublicadas.has(clavePublicada)
      ) {
        return false;
      }
      if (
        definicionesYaEnBorrador != null &&
        (definicionesYaEnBorrador.defIds.has(def.id) ||
          definicionesYaEnBorrador.claves.has(claveDefinicionBorrador(def)))
      ) {
        return false;
      }
      return true;
    });

    const construirInfo = async (lista: typeof defs): Promise<InfoDefinicion[]> => {
      const out: InfoDefinicion[] = [];
      for (const def of lista) {
        // Necesidad primero, operario como respaldo. Una plaza vacante deja
        // la definición completa sin agendar este mes (no a medias): se
        // excluye una vez por cada ocurrencia esperada, igual que el resto
        // de motivos de exclusión.
        const { operariosIds, necesidadesVacantes } = this.operariosIdsDeDefinicion(def);
        if (necesidadesVacantes) {
          const diasEsperados = pickDaysByFrecuencia(fechasDelMes, def);
          const prioridadDef = Number((def as any).prioridad ?? 2);
          const durMinDef = estimarDuracionDefinicionMin(def, tamanoBloqueMinutos);
          const mensaje = `La(s) plaza(s) requeridas por '${def.descripcion}' no tienen operario asignado.`;
          for (const diaEsperado of diasEsperados.length ? diasEsperados : [inicioMes]) {
            novedades.push({
              tipo: "SIN_CANDIDATAS",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad: prioridadDef,
              fecha: dayKey(diaEsperado),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              defId: def.id,
              fechaObjetivo: diaEsperado,
              duracionMinutos: Math.max(1, durMinDef),
              motivoTipo: "NECESIDAD_SIN_OPERARIO",
              motivoMensaje: mensaje,
            });
          }
          continue;
        }

        // Ventana de búsqueda de esta definición: la(s) plaza(s) si tienen
        // horario especial, o el horario general del conjunto (idéntico al
        // comportamiento previo cuando no hay necesidades involucradas).
        const horariosPorDiaDef = await this.horariosPorDiaParaOperarios(
          conjuntoId,
          operariosIds,
        );
        // Plaza(s) de esta definición: ¿trabajan festivos, y con qué
        // horario? (reemplaza la regla fija "solo SALVAVIDAS").
        const festivoHorarioDef = await this.festivoHorarioParaOperarios(
          conjuntoId,
          operariosIds,
        );

        const diasFrecuencia = pickDaysByFrecuencia(fechasDelMes, def);
        const puedeTrabajarFestivo = festivoHorarioDef != null;
        // Días de descanso compensatorio de estas plazas: bloquean igual que
        // un festivo no trabajable (ver diasDescansoParaOperarios).
        const diasDescansoDef = await this.diasDescansoParaOperarios(
          conjuntoId,
          operariosIds,
          inicioMes,
          finMes,
        );
        // Una preventiva DIARIA representa una ejecucion por cada jornada
        // laborable configurada. Generarla tambien en dias sin horario (por
        // ejemplo sabado y domingo) creaba ocurrencias extra que luego
        // intentaban repetirse en los dias habiles y terminaban excluidas.
        const dias =
          def.frecuencia === Frecuencia.DIARIA
            ? diasFrecuencia.filter(
                (dia) =>
                  resolverHorarioConFestivo(dia, horariosPorDiaDef, festivosSet, festivoHorarioDef) !=
                    null &&
                  (puedeTrabajarFestivo || !festivosSet.has(dayKey(dia))) &&
                  !diasDescansoDef.has(dayKey(dia)),
              )
            : diasFrecuencia;
        out.push({
          def,
          prioridad: Number((def as any).prioridad ?? 2),
          operariosIds,
          horariosPorDiaDef,
          festivoHorarioDef,
          diasDescansoDef,
          dias,
          durMin: estimarDuracionDefinicionMin(def, tamanoBloqueMinutos),
        });
      }
      return out;
    };

    const p1Info = await construirInfo(
      defsValidas.filter((def) => Number((def as any).prioridad ?? 2) === 1),
    );
    const p2Info = await construirInfo(
      defsValidas.filter((def) => Number((def as any).prioridad ?? 2) === 2),
    );
    const p3Info = await construirInfo(
      defsValidas.filter((def) => Number((def as any).prioridad ?? 2) === 3),
    );

    // Una P1 repetitiva de una sola jornada tiene fechas mucho menos flexibles:
    // si una P1 de varios días ocupa primero el tope semanal, las ocurrencias
    // DIARIAS desplazadas terminan sin una fecha distinta disponible al final
    // del mes. Se reservan primero todas las P1 de una jornada y luego se
    // reparten las partes de las P1 multidía por los huecos restantes. Ambas
    // fases siguen ejecutándose antes de permitir cualquier P2/P3.
    const esDefinicionMultiDia = (info: InfoDefinicion) =>
      Math.max(
        1,
        Math.floor(Number((info.def as any).diasParaCompletar ?? 1)),
      ) > 1;
    const p1UnaJornada = p1Info.filter(
      (info) => !esDefinicionMultiDia(info),
    );
    const p1MultiDia = p1Info.filter(esDefinicionMultiDia);

    // En las garantías P2/P3 (y dentro de un mismo nivel P1), escasez primero
    // y luego mayor duración. El orden especial entre niveles P1 se construye
    // más abajo para no sacrificar ocurrencias DIARIAS al final del mes.
    const ordenGarantia = (lista: InfoDefinicion[]) =>
      [...lista].sort(
        (a, b) =>
          a.dias.length - b.dias.length ||
          b.durMin - a.durMin ||
          a.def.id - b.def.id,
      );
    const ordenReparto = (lista: InfoDefinicion[]) =>
      [...lista].sort((a, b) => b.durMin - a.durMin || a.def.id - b.def.id);
    const construirRondas = (lista: InfoDefinicion[]): TrabajoOcurrencia[] => {
      const ordenBase = ordenReparto(lista);
      const maxDias = ordenBase.reduce(
        (max, info) => Math.max(max, info.dias.length),
        0,
      );
      const out: TrabajoOcurrencia[] = [];
      // La ronda 0 (dias[0]) ya se intentó en la garantía; el reparto
      // arranca en la ronda 1.
      for (let ronda = 1; ronda < maxDias; ronda++) {
        for (const info of ordenBase) {
          if (ronda < info.dias.length) {
            out.push({
              def: info.def,
              prioridad: info.prioridad,
              operariosIds: info.operariosIds,
              horariosPorDiaDef: info.horariosPorDiaDef,
              festivoHorarioDef: info.festivoHorarioDef,
              diasDescansoDef: info.diasDescansoDef,
              dia: info.dias[ronda],
              esRondaGarantia: false,
            });
          }
        }
      }
      return out;
    };

    const construirGarantia = (
      lista: InfoDefinicion[],
      esGarantiaP3: boolean,
    ): TrabajoOcurrencia[] => {
      const out: TrabajoOcurrencia[] = [];
      for (const info of ordenGarantia(lista)) {
        if (!info.dias.length) continue;
        out.push({
          def: info.def,
          prioridad: info.prioridad,
          operariosIds: info.operariosIds,
          horariosPorDiaDef: info.horariosPorDiaDef,
          festivoHorarioDef: info.festivoHorarioDef,
          diasDescansoDef: info.diasDescansoDef,
          dia: info.dias[0],
          esRondaGarantia: esGarantiaP3,
        });
      }
      return out;
    };

    const trabajos: TrabajoOcurrencia[] = [];
    // Dentro de las P1 de una jornada se atienden primero las definiciones
    // que necesitan más fechas distintas en el mes. Una DIARIA no puede
    // recuperar al final una fecha ocupada creando dos ocurrencias el mismo
    // día; en cambio una MENSUAL todavía puede moverse a cualquiera de los
    // huecos restantes. Las definiciones con igual cantidad de ocurrencias
    // siguen repartiéndose por rondas para que ninguna acapare la capacidad.
    const cantidadesOcurrenciasP1 = [
      ...new Set(p1UnaJornada.map((info) => info.dias.length)),
    ].sort((a, b) => b - a);
    for (const cantidad of cantidadesOcurrenciasP1) {
      const mismoNivelDeRigidez = p1UnaJornada.filter(
        (info) => info.dias.length === cantidad,
      );
      trabajos.push(...construirGarantia(mismoNivelDeRigidez, false));
      trabajos.push(...construirRondas(mismoNivelDeRigidez));
    }
    trabajos.push(...construirGarantia(p1MultiDia, false));
    trabajos.push(...construirRondas(p1MultiDia));
    trabajos.push(...construirGarantia(p2Info, false));
    trabajos.push(...construirGarantia(p3Info, true));
    trabajos.push(...construirRondas(p2Info));
    trabajos.push(...construirRondas(p3Info));

    for (const trabajo of trabajos) {
      const def = trabajo.def;
      const prioridad = trabajo.prioridad;
      const operariosIds = trabajo.operariosIds;
      // Ventana de búsqueda de ESTA definición (plaza con horario especial,
      // o el horario general del conjunto). Sustituye al `horariosPorDia`
      // conjunto-wide en todo el cuerpo de este bucle.
      const horariosPorDiaDef = trabajo.horariosPorDiaDef;
      const festivoHorarioDef = trabajo.festivoHorarioDef;
      const diasDescansoDef = trabajo.diasDescansoDef;
      // Días que bloquean esta definición: festivos que su(s) plaza(s) no
      // pueden trabajar (vacío si sí pueden, con su propio horario -ver
      // festivoHorarioDef-) UNION los días de descanso compensatorio de esas
      // mismas plazas (bloquean siempre, sin importar el rol).
      const festivosSetDef = new Set<string>([
        ...(festivoHorarioDef != null ? [] : festivosSet),
        ...diasDescansoDef,
      ]);
      const diasValidos = [trabajo.dia];

      for (const diaBase of diasValidos) {
        const minutosEstimados =
          calcularMinutosEstimados({
            cantidad:
              def.areaNumerica != null ? Number(def.areaNumerica) : undefined,
            rendimiento:
              def.rendimientoBase != null
                ? Number(def.rendimientoBase)
                : undefined,
            duracionMinutosFija: (def as any).duracionMinutosFija ?? undefined,
            rendimientoTiempoBase:
              (def as any).rendimientoTiempoBase ?? "POR_HORA",
          }) ??
          ((def as any).duracionMinutosFija != null
            ? Number((def as any).duracionMinutosFija)
            : null) ??
          ((def as any).duracionHorasFija != null
            ? Math.max(
                1,
                Math.round(Number((def as any).duracionHorasFija) * 60),
              )
            : null) ??
          null;
        const durMinTotal = minutosEstimados ?? tamanoBloqueMinutos;
        const ocurrenciaPlanId = await this.registrarOcurrenciaEsperada({
          def,
          conjuntoId,
          periodoAnio,
          periodoMes,
          fechaObjetivo: diaBase,
          duracionEsperadaMin: durMinTotal,
          operariosIds,
        });
        const esCoberturaMinimaP3 =
          prioridad === 3 && trabajo.esRondaGarantia;
        const diaProgramable = esCoberturaMinimaP3
          ? new Date(
              diaBase.getFullYear(),
              diaBase.getMonth(),
              diaBase.getDate(),
              0,
              0,
              0,
              0,
            )
          : resolverDiaObjetivo(diaBase, prioridad);
        if (!diaProgramable) {
          if (prioridad === 1) {
            const mensaje =
              `La tarea obligatoria '${def.descripcion}' no tiene un día hábil ` +
              `restante dentro de ${periodoAnio}-${String(periodoMes).padStart(2, "0")}.`;
            novedades.push({
              tipo: "SIN_HUECO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaBase),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaBase,
              duracionMinutos: Math.max(1, durMinTotal),
              motivoTipo: "SIN_CAPACIDAD_P1",
              motivoMensaje: mensaje,
            });
            continue;
          }
          const diaBaseEsDescanso = diasDescansoDef.has(dayKey(diaBase));
          const diaBaseEsFestivo = !diaBaseEsDescanso && festivosSetDef.has(dayKey(diaBase));
          const diaBaseEsDomingo =
            !diaBaseEsDescanso && dateToDiaSemana(diaBase) === DiaSemana.DOMINGO;
          if (diaBaseEsDescanso || diaBaseEsFestivo || diaBaseEsDomingo) {
            const motivo = diaBaseEsDescanso
              ? ("DESCANSO_COMPENSATORIO" as const)
              : diaBaseEsDomingo
                ? ("DOMINGO" as const)
                : ("FESTIVO" as const);
            const mensaje = diaBaseEsDescanso
              ? "La tarea cae en el descanso compensatorio de la plaza y no se programo en el periodo."
              : diaBaseEsDomingo
                ? "La tarea cae en domingo y no se programo en el periodo."
                : "La tarea cae en festivo y no se programo en el periodo.";
            novedades.push({
              tipo: "FESTIVO_OMITIDO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaBase),
              motivo,
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaBase,
              duracionMinutos: Math.max(1, durMinTotal),
              motivoTipo: diaBaseEsDescanso ? "DESCANSO_COMPENSATORIO" : "FESTIVO_OMITIDO",
              motivoMensaje: mensaje,
              metadataJson: { motivo },
            });
          } else {
            const mensaje =
              "No existe un día con horario válido desde la fecha objetivo hasta el cierre del periodo.";
            novedades.push({
              tipo: "SIN_HUECO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaBase),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaBase,
              duracionMinutos: Math.max(1, durMinTotal),
              motivoTipo: "SIN_HUECO",
              motivoMensaje: mensaje,
            });
          }
          continue;
        }

        // ✅ log: cayó en festivo/domingo/descanso y se movió
        const diaBaseEsFestivo = !diasDescansoDef.has(dayKey(diaBase)) && festivosSetDef.has(dayKey(diaBase));
        const diaBaseEsDomingo = dateToDiaSemana(diaBase) === DiaSemana.DOMINGO;
        if (
          (diaBaseEsFestivo || diaBaseEsDomingo || diasDescansoDef.has(dayKey(diaBase))) &&
          dayKey(diaProgramable) !== dayKey(diaBase)
        ) {
          novedades.push({
            tipo: "FESTIVO_MOVIDO",
            defId: def.id,
            descripcion: def.descripcion,
            prioridad,
            fechaOriginal: dayKey(diaBase),
            fechaNueva: dayKey(diaProgramable),
          });
        }

        // `durMinTotal` es la duración total de la ocurrencia. Cuando la
        // definición indica varios días, se divide en partes equilibradas y
        // cada parte se ubica en un día distinto. Dentro de uno de esos días
        // todavía puede partirse antes/después del almuerzo.
        const diasParaCompletar = Math.max(
          1,
          Math.floor(Number((def as any).diasParaCompletar ?? 1)),
        );
        const partesMin = splitMinutes(durMinTotal, diasParaCompletar);
        const grupoPlanId =
          partesMin.length > 1
            ? `BOR-${def.id}-${periodoAnio}-${periodoMes}-${randomUUID()}`
            : null;

        const totalBloquesEsperados = partesMin.length;
        let bloqueIndexCursor = 1;
        let partesAgendadas = 0;
        const diasUsadosPorPartes = new Set<string>();

        // cursor de día para las partes
        let cursorDia = new Date(diaProgramable);

        for (let p = 0; p < partesMin.length; p++) {
          const durMinParte = partesMin[p];

          let diaParte = esCoberturaMinimaP3
            ? new Date(
                cursorDia.getFullYear(),
                cursorDia.getMonth(),
                cursorDia.getDate(),
                0,
                0,
                0,
                0,
              )
            : resolverDiaObjetivo(cursorDia, prioridad);
          if (!diaParte) {
            // Si una tarea de varios días llega al borde del mes, continúa
            // buscando hacia atrás dentro del mismo periodo en vez de quedar
            // excluida inmediatamente por haber avanzado al mes siguiente.
            const referencia =
              +cursorDia < +inicioMes ? new Date(inicioMes) : new Date(finMes);
            referencia.setHours(0, 0, 0, 0);
            diaParte = referencia;
          }

          // Fecha objetivo real de esta parte: la fase de rescate busca a partir de aqui.
          const diaObjetivoParte = new Date(diaParte);

          let agendada = false;
          let diasConCandidatasP3ParaP2 = 0;
          let diasMesEvaluados: Date[] = [];
          const crearPayloadReemplazo = () => ({
            descripcion: def.descripcion,
            tipo: TipoTarea.PREVENTIVA,
            frecuencia: def.frecuencia ?? null,
            definicionId: def.id,
            ocurrenciaPlanId,
            diaSemanaProgramado: def.diaSemanaProgramado ?? null,
            prioridad,
            supervisorId: def.supervisorId
              ? def.supervisorId.toString()
              : null,
            ubicacionId: def.ubicacionId,
            elementoId: def.elementoId,
            conjuntoId,
            borrador: true,
            periodoAnio,
            periodoMes,
            insumosPlanJson: def.insumosPlanJson ?? undefined,
            maquinariaPlanJson: def.maquinariaPlanJson ?? undefined,
            herramientasPlanJson:
              (def as any).herramientasPlanJson ?? undefined,
            operariosIds,
            grupoPlanId,
            bloqueIndexBase: grupoPlanId ? bloqueIndexCursor : undefined,
            bloquesTotalesOverride: grupoPlanId
              ? totalBloquesEsperados
              : undefined,
            marcarComoReprogramada: false,
          });

          // La fase inicial prueba la fecha objetivo. Si una P1 no cabe, el
          // rescate posterior recorre días válidos y deja una causa explícita
          // únicamente cuando el mes no tiene capacidad real.
          const finSemanaBusqueda = new Date(diaParte);
          finSemanaBusqueda.setHours(23, 59, 59, 999);

          const maxDiasBusqueda = 1;
          for (let guardDia = 0; guardDia < maxDiasBusqueda; guardDia++) {
            if (!diaParte) break;
            if (prioridad === 2 && +diaParte > +finSemanaBusqueda) break;

            // Nunca crear bloques fuera del periodo solicitado.
            if (
              prioridad !== 1 &&
              (diaParte.getFullYear() !== periodoAnio ||
                diaParte.getMonth() + 1 !== periodoMes)
            ) {
              diaParte = null;
              break;
            }

            const diaParteKey = dayKey(diaParte);
            if (
              diasUsadosPorPartes.has(diaParteKey) ||
              this.hayOtraOcurrenciaDefinicionEnDia({
                definicionId: def.id,
                ocurrenciaPlanId,
                fecha: diaParte,
              })
            ) {
              break;
            }
            const esFestivo = festivosSetDef.has(diaParteKey);
            const disponibilidadOperarios = operariosIds.length
              ? await this.disponibilidadScheduler({
                  fecha: diaParte,
                  operariosIds,
                })
              : { ok: true, noDisponibles: [] as string[] };

            // Festivo, operario no disponible o dia sin horario: se abandona la fase A
            // y se delega en la fase de rescate, que barre el resto del periodo.
            if (esFestivo || !disponibilidadOperarios.ok) break;

            const horario = resolverHorarioConFestivo(diaParte, horariosPorDiaDef, festivosSet, festivoHorarioDef);
            if (!horario) break;

            // ✅ 1) Descanso
            const bloqueosDescanso = buildBloqueosPorDescanso(horario);

            // ✅ 2) Patrón jornada (bloqueos por operario)
            const bloqueosPatron = await this.bloqueosPatronScheduler({
              conjuntoId,
              fecha: diaParte,
              horario,
              operariosIds,
            });

            // ✅ 3) Bloqueos totales
            const bloqueos = [...bloqueosDescanso, ...bloqueosPatron];

            // agenda por operarios => ocupados global merged
            let ocupadosGlobal: Intervalo[] = [];

            if (operariosIds.length) {
              if (this.agendaSchedulerActiva) {
                ocupadosGlobal = this.ocupadosAgendaScheduler({
                  fecha: diaParte,
                  operariosIds,
                  incluirPublicadas: incluirPublicadasEnAgenda,
                  bloqueos,
                });
              } else {
                const agenda = await buildAgendaPorOperarioDia({
                  prisma: this.prisma,
                  conjuntoId,
                  fechaDia: diaParte,
                  operariosIds,
                  incluirBorrador: true,
                  bloqueosGlobales: bloqueos,
                  excluirEstados: ["PENDIENTE_REPROGRAMACION"],
                });

                const all: Intervalo[] = [];
                for (const opId of Object.keys(agenda)) {
                  all.push(...agenda[opId]);
                }
                ocupadosGlobal = mergeIntervalos(all);
              }
            } else {
              ocupadosGlobal = mergeIntervalos(
                bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })),
              );
            }

            // buscar hueco
            const bloquesFound = buscarHuecoDiaConSplitEarliest({
              startMin: horario.startMin,
              endMin: horario.endMin,
              durMin: durMinParte,
              ocupados: ocupadosGlobal,
              bloqueos,
              desiredStartMin: horario.startMin,
              maxBloques: 2,
              splitSoloPorDescanso: true,
            });

            if (bloquesFound) {
              // Todas las prioridades respetan la capacidad semanal real.
              // Si una P1 no cabe, continúa con el rescate dentro del mes.
              const pasaLimite = await this.cabeEnLimiteSemanal({
                conjuntoId,
                operariosIds,
                fechaReferencia: toDateAtMin(diaParte, bloquesFound[0].i),
                minutosAdicionales: durMinParte,
                horariosPorDia: horariosPorDiaDef,
                incluirPublicadasEnAgenda,
              });

              if (!pasaLimite) {
                break;
              }

              // ✅ crear tareas
              const nuevaTareaIds = await this.crearBloquesPreventivosDeDefinicion({
                def,
                conjuntoId,
                periodoAnio,
                periodoMes,
                ocurrenciaPlanId,
                prioridad,
                operariosIds,
                bloques: bloquesFound.map((b) => ({
                  fechaInicio: toDateAtMin(diaParte!, b.i),
                  fechaFin: toDateAtMin(diaParte!, b.f),
                })),
                grupoPlanId,
                bloqueIndexBase: bloqueIndexCursor,
                bloquesTotales: totalBloquesEsperados,
              });

              creadas += nuevaTareaIds.length;
              if (grupoPlanId) bloqueIndexCursor += nuevaTareaIds.length;

              agendada = true;
              break;
            }

            // Todas las prioridades pasan primero al rescate mensual. En P1,
            // si no existe capacidad libre completa, se prueban reemplazos en
            // cada día del mes antes de excluirla.
            break;
          }

          // Una P1 nunca puede extender la jornada. Si no cupo en su fecha
          // objetivo, se revisa todo el mes por proximidad: fecha objetivo,
          // días posteriores y anteriores, sin salir del periodo.
          if (!agendada && prioridad === 1) {
            const diasP1PorProximidad = ordenarDiasMesPorProximidad({
              dias: enumerateDays(inicioMes, finMes).filter(
                (dia) =>
                  !festivosSetDef.has(dayKey(dia)) &&
                  resolverHorarioConFestivo(dia, horariosPorDiaDef, festivosSet, festivoHorarioDef) !=
                    null,
              ),
              fechaObjetivo: diaObjetivoParte,
              periodoAnio,
              periodoMes,
            });
            const diasP1 = this.priorizarDiasSinRepetirDefinicion({
              dias: diasP1PorProximidad,
              definicionId: def.id,
              ocurrenciaPlanId,
            }).filter((dia) => !diasUsadosPorPartes.has(dayKey(dia)));

            // Se mantiene cada parte de la P1 en un solo día: primero un bloque
            // continuo y, si no existe, dos bloques pegados al descanso. Una
            // parte no se fragmenta por huecos arbitrarios ni entre varios días.
            let planP1: BloqueProgramacion[] = [];
            for (const diaCandidato of diasP1) {
              planP1 = await this.construirPlanEnRango({
                conjuntoId,
                duracionMinutos: durMinParte,
                operariosIds,
                dias: [diaCandidato],
                horariosPorDia: horariosPorDiaDef,
                festivosSet: festivosSetDef,
                festivosSetRaw: festivosSet,
                festivoHorario: festivoHorarioDef,
                maxBloquesPorDia: 2,
                permitirMultiDia: false,
                validarLimiteSemanal: true,
                incluirPublicadasEnAgenda,
                splitSoloPorDescanso: true,
              });
              if (planP1.length) break;
            }

            if (planP1.length) {
              const nuevaTareaIds = await this.crearBloquesPreventivosDeDefinicion({
                def,
                conjuntoId,
                periodoAnio,
                periodoMes,
                ocurrenciaPlanId,
                prioridad,
                operariosIds,
                bloques: planP1,
                grupoPlanId,
                bloqueIndexBase: bloqueIndexCursor,
                bloquesTotales: totalBloquesEsperados,
              });
              creadas += nuevaTareaIds.length;
              if (grupoPlanId) bloqueIndexCursor += nuevaTareaIds.length;
              const fechaNueva = dayKey(planP1[0].fechaInicio);
              const fechaObjetivo = dayKey(diaObjetivoParte);
              const mensaje =
                fechaNueva === fechaObjetivo
                  ? "La tarea P1 se dividió en bloques válidos dentro de su fecha objetivo."
                  : `La tarea P1 no cabía en ${fechaObjetivo} y se reubicó en ${fechaNueva}.`;
              novedades.push({
                tipo: "REUBICADA_EN_PERIODO",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: fechaNueva,
                fechaObjetivo,
                nuevaTareaIds,
                bloques: planP1.map((bloque) => ({
                  fechaInicio: bloque.fechaInicio.toISOString(),
                  fechaFin: bloque.fechaFin.toISOString(),
                })),
                mensaje,
              });
              await this.registrarEventoBorrador({
                conjuntoId,
                periodoAnio,
                periodoMes,
                tipo: "REUBICADA_EN_PERIODO",
                accionAuditoria: AccionAuditoria.CREAR,
                origenAuditoria: OrigenAuditoria.SCHEDULER,
                detalle: mensaje,
                tareaId: nuevaTareaIds[0] ?? null,
                metadataJson: {
                  defId: def.id,
                  prioridad,
                  fechaObjetivo,
                  fechaNueva,
                  nuevaTareaIds,
                },
              });
              agendada = true;
              diaParte = planP1[planP1.length - 1].fechaInicio;
            }

            // Si no bastaron los huecos libres, se intenta desplazar una o
            // varias P3/P2 en cada día válido del mes. El reemplazo solo
            // divide la P1 en dos tramos contiguos al descanso y nunca deja
            // huecos laborales arbitrarios entre las partes.
            if (!agendada) {
              for (const diaAlternativo of diasP1) {
                const disponibilidad = operariosIds.length
                  ? await this.disponibilidadScheduler({
                      fecha: diaAlternativo,
                      operariosIds,
                    })
                  : { ok: true, noDisponibles: [] as string[] };
                if (!disponibilidad.ok) continue;

                const horario = resolverHorarioConFestivo(
                  diaAlternativo,
                  horariosPorDiaDef,
                  festivosSet,
                  festivoHorarioDef,
                );
                if (!horario) continue;
                const bloqueos = [
                  ...buildBloqueosPorDescanso(horario),
                  ...(await this.bloqueosPatronScheduler({
                    conjuntoId,
                    fecha: diaAlternativo,
                    horario,
                    operariosIds,
                  })),
                ];

                const reemplazo = await intentarReemplazoPorPrioridadBaja({
                  prisma: this.prisma,
                  conjuntoId,
                  fechaDia: diaAlternativo,
                  startMin: horario.startMin,
                  endMin: horario.endMin,
                  bloqueos,
                  durMin: durMinParte,
                  payload: crearPayloadReemplazo(),
                  prioridadesCandidatas: [3, 2],
                  incluirBorradorEnAgenda: true,
                  incluirPublicadasEnAgenda,
                  splitSoloPorDescanso: true,
                });
                if (!reemplazo.ok) continue;

                await this.moverReemplazadasAExcluidas({
                  tareaIds: reemplazo.reprogramadasIds,
                  reemplazadaPorDefId: def.id,
                  reemplazadaPorDescripcion: def.descripcion,
                });
                this.minutosSemanaSchedulerCache.clear();
                this.retirarTareasAgendaScheduler(
                  reemplazo.reprogramadasIds,
                );
                reemplazo.bloques.forEach((bloque, index) => {
                  const tareaId = reemplazo.nuevaTareaIds[index];
                  if (tareaId == null) return;
                  this.registrarIntervaloAgendaScheduler({
                    tareaId,
                    fechaInicio: toDateAtMin(diaAlternativo, bloque.i),
                    fechaFin: toDateAtMin(diaAlternativo, bloque.f),
                    operariosIds,
                    borrador: true,
                  });
                });
                this.registrarOcurrenciaDefinicionDiaScheduler({
                  definicionId: def.id,
                  ocurrenciaPlanId,
                  bloques: reemplazo.bloques.map((bloque) => ({
                    fechaInicio: toDateAtMin(diaAlternativo, bloque.i),
                    fechaFin: toDateAtMin(diaAlternativo, bloque.f),
                  })),
                });
                creadas += reemplazo.nuevaTareaIds.length;
                await this.reconciliarOcurrenciaProgramada(
                  ocurrenciaPlanId,
                );
                if (grupoPlanId) {
                  bloqueIndexCursor += reemplazo.nuevaTareaIds.length;
                }

                const fechaNueva = dayKey(diaAlternativo);
                const fechaObjetivo = dayKey(diaObjetivoParte);
                const mensaje =
                  `La tarea P1 se programó en ${fechaNueva} desplazando ` +
                  `${reemplazo.reprogramadasIds.length} tarea(s) de menor prioridad` +
                  `${reemplazo.bloques.length > 1 ? ` y dividiéndose en ${reemplazo.bloques.length} bloques` : ""}.`;
                novedades.push({
                  tipo: "REEMPLAZO_PRIORIDAD",
                  defId: def.id,
                  descripcion: def.descripcion,
                  prioridad,
                  fecha: fechaNueva,
                  nuevaTareaIds: reemplazo.nuevaTareaIds,
                  reprogramadasIds: reemplazo.reprogramadasIds,
                  mensaje,
                });
                await this.registrarEventoBorrador({
                  conjuntoId,
                  periodoAnio,
                  periodoMes,
                  tipo: "REEMPLAZO_PRIORIDAD",
                  accionAuditoria: AccionAuditoria.REEMPLAZAR,
                  origenAuditoria: OrigenAuditoria.SCHEDULER,
                  detalle: mensaje,
                  tareaId: reemplazo.nuevaTareaIds[0] ?? null,
                  metadataJson: {
                    defId: def.id,
                    prioridad,
                    fechaObjetivo,
                    fechaNueva,
                    nuevaTareaIds: reemplazo.nuevaTareaIds,
                    reprogramadasIds: reemplazo.reprogramadasIds,
                    bloques: reemplazo.bloques,
                  },
                });
                agendada = true;
                diaParte = diaAlternativo;
                break;
              }
            }
          }

          // ============================================================
          // Fase B - rescate mensual para P2/P3. P1 ya tuvo arriba su rescate
          // por proximidad y sus intentos de reemplazo de prioridades menores.
          // ============================================================
          if (!agendada && prioridad !== 1) {
            const diasRescate = await this.diasMesPorAprovechamiento({
              conjuntoId,
              fechaObjetivo: diaObjetivoParte,
              periodoAnio,
              periodoMes,
              operariosIds,
              horariosPorDia: horariosPorDiaDef,
              festivosSet: festivosSetDef,
              festivosSetRaw: festivosSet,
              festivoHorario: festivoHorarioDef,
              definicionId: def.id,
              descripcion: def.descripcion,
              ubicacionId: def.ubicacionId,
              elementoId: def.elementoId,
            });
            diasMesEvaluados = diasRescate;

            if (diasRescate.length) {
              // Elegir un único día que aloje la ocurrencia completa. Solo se
              // permiten dos bloques si rodean exactamente el almuerzo.
              const planRescate = await this.construirMejorPlanEnDias({
                conjuntoId,
                duracionMinutos: durMinParte,
                operariosIds,
                dias: diasRescate,
                horariosPorDia: horariosPorDiaDef,
                festivosSet: festivosSetDef,
                festivosSetRaw: festivosSet,
                festivoHorario: festivoHorarioDef,
                incluirPublicadasEnAgenda,
              });

              if (planRescate.length) {
                const nuevaTareaIds = await this.crearBloquesPreventivosDeDefinicion({
                  def,
                  conjuntoId,
                  periodoAnio,
                  periodoMes,
                  ocurrenciaPlanId,
                  prioridad,
                  operariosIds,
                  bloques: planRescate,
                  grupoPlanId,
                  bloqueIndexBase: bloqueIndexCursor,
                  bloquesTotales: totalBloquesEsperados,
                });

                creadas += nuevaTareaIds.length;
                if (grupoPlanId) bloqueIndexCursor += nuevaTareaIds.length;

                const claveObjetivo = dayKey(diaObjetivoParte);
                const fechaNueva = dayKey(planRescate[0].fechaInicio);
                const bloquesSerializados = planRescate.map((bloque) => ({
                  fechaInicio: bloque.fechaInicio.toISOString(),
                  fechaFin: bloque.fechaFin.toISOString(),
                }));

                const seMovioDeDia = fechaNueva !== claveObjetivo;
                const mensaje = seMovioDeDia
                  ? `No habia espacio el ${claveObjetivo}; la tarea se reubico en ${fechaNueva}${
                      planRescate.length > 1 ? ` repartida en ${planRescate.length} bloques` : ""
                    }.`
                  : `La tarea se dividio en ${planRescate.length} bloques dentro del ${claveObjetivo} para aprovechar los huecos disponibles.`;

                novedades.push({
                  tipo: "REUBICADA_EN_PERIODO",
                  defId: def.id,
                  descripcion: def.descripcion,
                  prioridad,
                  fecha: fechaNueva,
                  fechaObjetivo: claveObjetivo,
                  nuevaTareaIds,
                  bloques: bloquesSerializados,
                  mensaje,
                });

                await this.registrarEventoBorrador({
                  conjuntoId,
                  periodoAnio,
                  periodoMes,
                  tipo: "REUBICADA_EN_PERIODO",
                  accionAuditoria: AccionAuditoria.CREAR,
                  origenAuditoria: OrigenAuditoria.SCHEDULER,
                  detalle: mensaje,
                  tareaId: nuevaTareaIds[0] ?? null,
                  metadataJson: {
                    defId: def.id,
                    prioridad,
                    fechaObjetivo: claveObjetivo,
                    fechaNueva,
                    seMovioDeDia,
                    nuevaTareaIds,
                    bloques: bloquesSerializados,
                  },
                });

                agendada = true;
                diaParte = planRescate[planRescate.length - 1].fechaInicio;
              }
            }
          }

          // Fase C: si tampoco hubo hueco libre, aplicar la jerarquía de
          // reemplazo en los demás días del mes. Esto es especialmente
          // importante para tareas compartidas, cuyo hueco común puede estar
          // en miércoles o jueves aunque el objetivo fuera lunes.
          if (!agendada && prioridad === 2) {
            const prioridadesCandidatas: Array<2 | 3> = [3];

            for (const diaAlternativo of diasMesEvaluados) {
              const disponibilidad = operariosIds.length
                ? await this.disponibilidadScheduler({
                    fecha: diaAlternativo,
                    operariosIds,
                  })
                : { ok: true, noDisponibles: [] as string[] };
              if (!disponibilidad.ok) continue;

              const horario = resolverHorarioConFestivo(
                diaAlternativo,
                horariosPorDiaDef,
                festivosSet,
                festivoHorarioDef,
              );
              if (!horario) continue;
              const bloqueos = [
                ...buildBloqueosPorDescanso(horario),
                ...(await this.bloqueosPatronScheduler({
                  conjuntoId,
                  fecha: diaAlternativo,
                  horario,
                  operariosIds,
                })),
              ];

              const reemplazo = await intentarReemplazoPorPrioridadBaja({
                prisma: this.prisma,
                conjuntoId,
                fechaDia: diaAlternativo,
                startMin: horario.startMin,
                endMin: horario.endMin,
                bloqueos,
                durMin: durMinParte,
                payload: crearPayloadReemplazo(),
                prioridadesCandidatas,
                ocurrenciasProtegidasIds: ocurrenciasP3MinimasProtegidas,
                incluirBorradorEnAgenda: true,
                incluirPublicadasEnAgenda,
                splitSoloPorDescanso: true,
              });
              if (!reemplazo.ok) {
                if (prioridad === 2 && reemplazo.reason === "SIN_HUECO") {
                  diasConCandidatasP3ParaP2++;
                }
                continue;
              }

              await this.moverReemplazadasAExcluidas({
                tareaIds: reemplazo.reprogramadasIds,
                reemplazadaPorDefId: def.id,
                reemplazadaPorDescripcion: def.descripcion,
              });
              this.minutosSemanaSchedulerCache.clear();
              this.retirarTareasAgendaScheduler(reemplazo.reprogramadasIds);
              reemplazo.bloques.forEach((bloque, index) => {
                const tareaId = reemplazo.nuevaTareaIds[index];
                if (tareaId == null) return;
                this.registrarIntervaloAgendaScheduler({
                  tareaId,
                  fechaInicio: toDateAtMin(diaAlternativo, bloque.i),
                  fechaFin: toDateAtMin(diaAlternativo, bloque.f),
                  operariosIds,
                  borrador: true,
                });
              });
              this.registrarOcurrenciaDefinicionDiaScheduler({
                definicionId: def.id,
                ocurrenciaPlanId,
                bloques: reemplazo.bloques.map((bloque) => ({
                  fechaInicio: toDateAtMin(diaAlternativo, bloque.i),
                  fechaFin: toDateAtMin(diaAlternativo, bloque.f),
                })),
              });
              creadas += reemplazo.nuevaTareaIds.length;
              await this.reconciliarOcurrenciaProgramada(ocurrenciaPlanId);
              if (grupoPlanId) {
                bloqueIndexCursor += reemplazo.nuevaTareaIds.length;
              }
              if (reemplazo.reprogramadasIds.length) {
                novedades.push({
                  tipo: "REEMPLAZO_PRIORIDAD",
                  defId: def.id,
                  descripcion: def.descripcion,
                  prioridad,
                  fecha: dayKey(diaAlternativo),
                  nuevaTareaIds: reemplazo.nuevaTareaIds,
                  reprogramadasIds: reemplazo.reprogramadasIds,
                  mensaje:
                    "Reemplazo automático en el mejor día disponible del mes.",
                });
              }
              agendada = true;
              diaParte = diaAlternativo;
              break;
            }
          }

          if (!agendada && prioridad === 3) {
            const mensaje =
              "No se encontro espacio disponible en el mes para esta tarea de prioridad 3.";
            novedades.push({
              tipo: "SIN_HUECO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaObjetivoParte),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaObjetivoParte,
              duracionMinutos: durMinParte,
              motivoTipo: "SIN_HUECO",
              motivoMensaje: mensaje,
            });
          }

          if (!agendada && prioridad === 2) {
            const encontroCandidatas = diasConCandidatasP3ParaP2 > 0;
            const motivoTipo = encontroCandidatas ? "SIN_HUECO" : "SIN_CANDIDATAS";
            const mensaje = encontroCandidatas
              ? "Las tareas P3 disponibles en el mes no liberaron capacidad suficiente para programar esta P2."
              : "No existe capacidad libre ni tareas P3 desplazables en los dias habiles restantes del mes.";
            novedades.push({
              tipo: motivoTipo,
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaObjetivoParte),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaObjetivoParte,
              duracionMinutos: durMinParte,
              motivoTipo,
              motivoMensaje: mensaje,
            });
          }

          if (!agendada && prioridad === 1) {
            const mensaje =
              `No fue posible programar la tarea obligatoria '${def.descripcion}' ` +
              `en ningún intervalo válido restante del mes.`;
            novedades.push({
              tipo: "SIN_HUECO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaObjetivoParte),
              mensaje,
            });
            await this.crearExcluidaDesdeDefinicion({
              conjuntoId,
              periodoAnio,
              periodoMes,
              ocurrenciaPlanId,
              defId: def.id,
              fechaObjetivo: diaObjetivoParte,
              duracionMinutos: durMinParte,
              motivoTipo: "SIN_CAPACIDAD_P1",
              motivoMensaje: mensaje,
            });
          }

          if (agendada && diaParte) {
            diasUsadosPorPartes.add(dayKey(diaParte));
            partesAgendadas++;
          }

          // mover cursor al siguiente día (para la siguiente parte)
          cursorDia = new Date(diaParte ?? cursorDia);
          cursorDia.setDate(cursorDia.getDate() + 1);

          if (!agendada) break;
        }
        if (
          trabajo.esRondaGarantia &&
          prioridad === 3 &&
          partesAgendadas === partesMin.length
        ) {
          ocurrenciasP3MinimasProtegidas.add(ocurrenciaPlanId);
        }
      }
    }

    // Rescate por capacidades: antes de dejar excluida una tarea por falta de
    // cupo, se busca otra plaza compatible (perfil con esa categoria entre sus
    // capacidades) con disponibilidad real. Solo puede reducir las excluidas.
    const rescateCapacidad = await this.rescatarExcluidasPorCapacidad({
      conjuntoId,
      periodoAnio,
      periodoMes,
      defsPorId: new Map(defs.map((def) => [def.id, def])),
      festivosSet,
      incluirPublicadasEnAgenda,
      novedades,
    });
    creadas += rescateCapacidad.tareasCreadas;
    this.rastreoExcluidas = false;
    this.excluidasDeLaCorrida = [];

    // Orden del dia: pasada global que mezcla tareas de varias definiciones y
    // plazas por dia. Resuelve el horario POR COMPONENTE (los operarios que
    // comparten las tareas agrupadas), no uno solo por dia para todo el
    // conjunto: asi una plaza con horario especial conserva su propia ventana
    // (ver reordenarBorradorGeneradoPorCategoria).
    const ordenamientoDia =
      modo === "RESET"
        ? await this.reordenarBorradorGeneradoPorCategoria({
            conjuntoId,
            periodoAnio,
            periodoMes,
          })
        : { reordenadas: 0, componentesSinOrdenar: 0 };

    if (
      ordenamientoDia.reordenadas > 0 ||
      ordenamientoDia.componentesSinOrdenar > 0
    ) {
      await this.registrarEventoBorrador({
        conjuntoId,
        periodoAnio,
        periodoMes,
        tipo: "ORDEN_CATEGORIAS_APLICADO",
        detalle:
          ordenamientoDia.componentesSinOrdenar > 0
            ? "Se ordenaron las horas por categoria; algunos grupos conservaron su horario por restricciones de agenda."
            : "Se ordenaron las horas del borrador por categoria y orden interno.",
        metadataJson: ordenamientoDia,
      });
    }

    await this.auditarGeneracionBorrador({
      conjuntoId,
      periodoAnio,
      periodoMes,
      creadas,
      novedades,
    });

    const versionesDefiniciones: VersionDefinicionBorrador[] = defs.map((def) => {
      const yaEstabaEnBorrador =
        definicionesYaEnBorrador != null &&
        (definicionesYaEnBorrador.defIds.has(def.id) ||
          definicionesYaEnBorrador.claves.has(claveDefinicionBorrador(def)));
      return {
        id: def.id,
        // CONSERVAR no vuelve a generar lo ya planificado: mantener su versión
        // anterior permite seguir avisando si esa definición fue modificada.
        actualizadoEn:
          yaEstabaEnBorrador && versionesAnteriores.has(def.id)
            ? versionesAnteriores.get(def.id)!
            : versionActualDefinicion(def),
      };
    });

    // Lo que quedó sin tarea, excluida ni ocurrencia tras generar no toca este
    // periodo (o no se puede planificar): se deja constancia para no avisarlo
    // como "nueva" en cada visita.
    let definicionesSinOcurrencia: number[] = [];
    try {
      const resultadoFinal = await this.definicionesConBorrador({
        conjuntoId,
        periodoAnio,
        periodoMes,
      });
      definicionesSinOcurrencia = defs
        .filter(
          (def) =>
            !resultadoFinal.defIds.has(def.id) &&
            !resultadoFinal.claves.has(claveDefinicionBorrador(def)),
        )
        .map((def) => def.id);
    } catch {
      // Dato informativo: si no se puede calcular, no debe abortar la
      // generación; solo volverían a avisarse esas preventivas como nuevas.
    }

    await this.registrarEventoBorrador({
      conjuntoId,
      periodoAnio,
      periodoMes,
      tipo: "BORRADOR_GENERADO",
      accionAuditoria: AccionAuditoria.GENERAR_BORRADOR,
      origenAuditoria: OrigenAuditoria.SCHEDULER,
      detalle:
        modo === "CONSERVAR"
          ? "Se incorporaron preventivas al borrador guardado."
          : "Se generó un nuevo borrador mensual.",
      metadataJson: {
        modo,
        versionesDefiniciones,
        definicionesSinOcurrencia,
        ordenamientoDia,
        rescateCapacidad: {
          reasignadas: rescateCapacidad.reasignadas,
          sinRecursoCompatible: rescateCapacidad.sinRecursoCompatible,
        },
      },
    });

    return { creadas, novedades };
  }

  /**
   * Deja constancia de quien genero el borrador y de cada tarea creada por el scheduler.
   * Se consultan las tareas al final en vez de acumular ids durante el bucle, para cubrir
   * tambien las que nacen por reemplazo de prioridad.
   */
  private async auditarGeneracionBorrador(params: {
    conjuntoId: string;
    periodoAnio: number;
    periodoMes: number;
    creadas: number;
    novedades: NovedadCronograma[];
  }) {
    const { conjuntoId, periodoAnio, periodoMes, creadas, novedades } = params;

    const excluidas = novedades.filter(
      (novedad) =>
        novedad.tipo === "SIN_HUECO" ||
        novedad.tipo === "SIN_CANDIDATAS" ||
        novedad.tipo === "REQUIERE_CONFIRMACION_REEMPLAZO" ||
        novedad.tipo === "FESTIVO_OMITIDO",
    ).length;
    const reubicadas = novedades.filter(
      (novedad) => novedad.tipo === "REUBICADA_EN_PERIODO",
    ).length;

    await this.auditoria.registrar({
      modulo: ModuloAuditoria.CRONOGRAMA,
      entidad: EntidadAuditoria.CRONOGRAMA_PERIODO,
      entidadId: `${conjuntoId}-${periodoAnio}-${periodoMes}`,
      accion: AccionAuditoria.GENERAR_BORRADOR,
      conjuntoId,
      actor: this.actor,
      descripcion: `Se genero el borrador de ${periodoMes}/${periodoAnio}: ${creadas} tarea(s) creadas, ${reubicadas} reubicada(s), ${excluidas} excluida(s).`,
      periodoAnio,
      periodoMes,
      metadataJson: { creadas, reubicadas, excluidas, novedades: novedades.length },
    });

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        periodoAnio,
        periodoMes,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
      },
      select: {
        id: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        definicionId: true,
      },
    });

    await this.auditoria.registrarLote(
      tareas.map((tarea) => ({
        modulo: ModuloAuditoria.TAREA,
        entidad: EntidadAuditoria.TAREA,
        entidadId: tarea.id,
        accion: AccionAuditoria.CREAR,
        conjuntoId,
        actor: this.actor,
        origen: OrigenAuditoria.SCHEDULER,
        descripcion: `El generador de cronograma creo la tarea '${tarea.descripcion}'.`,
        periodoAnio,
        periodoMes,
        datosDespues: {
          fechaInicio: tarea.fechaInicio,
          fechaFin: tarea.fechaFin,
          definicionId: tarea.definicionId,
        },
      })),
    );
  }

  async editarTareaBorrador(payload: unknown) {
    const dto = EditarBorradorDTO.parse(payload);

    const t = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      select: {
        id: true,
        borrador: true,
        conjuntoId: true,
        fechaInicio: true,
        fechaFin: true,
        ocurrenciaPlanId: true,
        grupoPlanId: true,
        definicionId: true,
        descripcion: true,
        ubicacionId: true,
        elementoId: true,
        operarios: { select: { id: true } },
      },
    });
    if (!t || !t.borrador || t.conjuntoId !== dto.conjuntoId) {
      throw new Error(
        "Tarea no existe, no es borrador o no pertenece a este conjunto.",
      );
    }
    const fechaInicio = dto.fechaInicio ?? t.fechaInicio;
    const fechaFin = dto.fechaFin ?? t.fechaFin;
    const operariosIds =
      dto.operariosIds?.map(String) ?? t.operarios.map((operario) => operario.id);
    await this.validarSlotPreventivaBorrador({
      conjuntoId: dto.conjuntoId,
      fechaInicio,
      fechaFin,
      operariosIds,
      excluirTareaId: dto.tareaId,
      // Solo si cambia de día: no se bloquean ediciones (operarios, horas)
      // por duplicados que ya existían.
      identidad:
        dayKey(fechaInicio) !== dayKey(t.fechaInicio) ? t : undefined,
    });
    await this.validarEdicionMantieneDivisionAlmuerzo({
      tareaId: t.id,
      conjuntoId: dto.conjuntoId,
      ocurrenciaPlanId: t.ocurrenciaPlanId,
      grupoPlanId: t.grupoPlanId,
      fechaInicio,
      fechaFin,
    });

    const actualizada = await this.prisma.tarea.update({
      where: { id: dto.tareaId },
      data: {
        fechaInicio: dto.fechaInicio ?? undefined,
        fechaFin: dto.fechaFin ?? undefined,
        duracionMinutos: Math.max(
          1,
          Math.round((+fechaFin - +fechaInicio) / 60000),
        ),
        operarios:
          dto.operariosIds !== undefined
            ? { set: dto.operariosIds.map((id) => ({ id: id.toString() })) }
            : undefined,
      },
      include: { operarios: { select: { id: true } } },
    });
    if (t.ocurrenciaPlanId) {
      await this.reconciliarOcurrenciaProgramada(t.ocurrenciaPlanId);
    }
    return actualizada;
  }

  async crearBloqueBorrador(conjuntoId: string, payload: unknown) {
    const dto = CrearBloqueBorradorDTO.parse(payload);
    await this.validarSlotPreventivaBorrador({
      conjuntoId,
      fechaInicio: dto.fechaInicio,
      fechaFin: dto.fechaFin,
      operariosIds: (dto.operariosIds ?? []).map(String),
    });

    const anio = dto.fechaInicio.getFullYear();
    const mes = dto.fechaInicio.getMonth() + 1;

    const creada = await this.prisma.tarea.create({
      data: {
        descripcion: dto.descripcion,
        fechaInicio: dto.fechaInicio,
        fechaFin: dto.fechaFin,
        duracionMinutos: Math.max(
          1,
          Math.round((+dto.fechaFin - +dto.fechaInicio) / 60000),
        ),
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: null,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        grupoPlanId: null,

        ubicacionId: dto.ubicacionId,
        elementoId: dto.elementoId,
        conjuntoId,
        supervisorId:
          dto.supervisorId == null ? null : dto.supervisorId.toString(),

        tiempoEstimadoMinutos:
          dto.tiempoEstimadoMinutos === undefined
            ? null
            : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),

        operarios: dto.operariosIds?.length
          ? { connect: dto.operariosIds.map((id) => ({ id: id.toString() })) }
          : undefined,
      },
    });

    await this.auditarTarea({
      tareaId: creada.id,
      conjuntoId,
      accion: AccionAuditoria.CREAR,
      descripcion: `Se agrego manualmente la tarea '${creada.descripcion}' al borrador.`,
      periodoAnio: anio,
      periodoMes: mes,
      datosDespues: {
        fechaInicio: creada.fechaInicio,
        fechaFin: creada.fechaFin,
        operariosIds: dto.operariosIds ?? [],
      },
    });

    return creada;
  }

  async editarBloqueBorrador(
    conjuntoId: string,
    tareaId: number,
    payload: unknown,
  ) {
    const dto = EditarBloqueBorradorDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: {
        id: true,
        conjuntoId: true,
        borrador: true,
        tipo: true,
        descripcion: true,
        grupoPlanId: true,
        maquinariaPlanJson: true,
        fechaInicio: true,
        fechaFin: true,
        ocurrenciaPlanId: true,
        definicionId: true,
        ubicacionId: true,
        elementoId: true,
        operarios: { select: { id: true } },
      },
    });

    if (
      !tarea ||
      tarea.conjuntoId !== conjuntoId ||
      !tarea.borrador ||
      tarea.tipo !== TipoTarea.PREVENTIVA
    ) {
      throw new Error("No es un bloque borrador preventivo de este conjunto.");
    }

    let operariosIdsFinal: string[] = [];

    if (dto.operariosIds) {
      operariosIdsFinal = dto.operariosIds.map((id) => id.toString());
    } else {
      operariosIdsFinal = tarea.operarios.map((o) => o.id);
    }

    const fechaInicio = dto.fechaInicio ?? tarea.fechaInicio;
    const fechaFin = dto.fechaFin ?? tarea.fechaFin;

    await this.validarSlotPreventivaBorrador({
      conjuntoId,
      fechaInicio,
      fechaFin,
      operariosIds: operariosIdsFinal,
      excluirTareaId: tareaId,
      identidad:
        dayKey(fechaInicio) !== dayKey(tarea.fechaInicio) ? tarea : undefined,
    });
    await this.validarEdicionMantieneDivisionAlmuerzo({
      tareaId: tarea.id,
      conjuntoId,
      ocurrenciaPlanId: tarea.ocurrenciaPlanId,
      grupoPlanId: tarea.grupoPlanId,
      fechaInicio,
      fechaFin,
    });

    if (fechaInicio) {
      const inicioEsFestivo = await isFestivoDate({
        prisma: this.prisma,
        fecha: fechaInicio,
        pais: "CO",
      });
      if (inicioEsFestivo) {
        // La plaza (necesidad operativa) de cada operario decide si trabaja
        // festivos, con su propio horario -no depende del rol-.
        const puedenTrabajarFestivo =
          operariosIdsFinal.length > 0 &&
          (await operariosPuedenTrabajarFestivo({
            prisma: this.prisma,
            conjuntoId,
            operariosIds: operariosIdsFinal,
          }));
        if (!puedenTrabajarFestivo) {
          throw new Error("No se permite programar tareas preventivas en festivos.");
        }
      }

      if (operariosIdsFinal.length) {
        const disponibilidad = await validarOperariosDisponiblesEnFecha({
          prisma: this.prisma,
          fecha: fechaInicio,
          operariosIds: operariosIdsFinal.map(String),
        });
        if (!disponibilidad.ok) {
          throw new Error(
            await construirMensajeSinDisponibilidadOperarios(
              this.prisma,
              disponibilidad.noDisponibles,
            ),
          );
        }
      }
    }

    if (fechaInicio && fechaFin && operariosIdsFinal.length) {
      const solapes = await Promise.all(
        operariosIdsFinal.map(async (opId) => ({
          opId,
          haySolape: await existeSolapeParaOperario(this.prisma, {
            conjuntoId,
            operarioId: opId,
            fechaInicio,
            fechaFin,
            soloBorrador: true,
            excluirTareaId: tareaId,
          }),
        })),
      );

      const conflicto = solapes.find((item) => item.haySolape);
      if (conflicto) {
        const nombre = await getOperarioNombre(this.prisma, conflicto.opId);
        throw new Error(`Solape de agenda con operario ${nombre}`);
      }
    }

    const actualizada = await this.prisma.tarea.update({
      where: { id: tareaId },
      include: tareaBorradorDetalleInclude,
      data: {
        descripcion: dto.descripcion ?? undefined,
        fechaInicio,
        fechaFin,
        duracionMinutos: Math.max(
          1,
          Math.round((+fechaFin - +fechaInicio) / 60000),
        ),
        ubicacionId: dto.ubicacionId ?? undefined,
        elementoId: dto.elementoId ?? undefined,
        supervisorId:
          dto.supervisorId === undefined
            ? undefined
            : dto.supervisorId === null
              ? null
              : dto.supervisorId.toString(),
        tiempoEstimadoMinutos:
          dto.tiempoEstimadoMinutos === undefined
            ? undefined
            : dto.tiempoEstimadoMinutos === null
              ? null
              : Math.max(0, Math.round(dto.tiempoEstimadoMinutos)),

        operarios:
          dto.operariosIds === undefined
            ? undefined
            : { set: dto.operariosIds.map((id) => ({ id: id.toString() })) },
      },
    });

    await this.auditarTarea({
      tareaId,
      conjuntoId,
      accion: AccionAuditoria.EDITAR,
      descripcion: `Se edito la tarea '${actualizada.descripcion}' en el borrador.`,
      periodoAnio: actualizada.periodoAnio,
      periodoMes: actualizada.periodoMes,
      datosDespues: {
        fechaInicio: actualizada.fechaInicio,
        fechaFin: actualizada.fechaFin,
        duracionMinutos: actualizada.duracionMinutos,
      },
      metadataJson: { camposEnviados: Object.keys(dto) },
    });

    if (tarea.ocurrenciaPlanId) {
      await this.reconciliarOcurrenciaProgramada(tarea.ocurrenciaPlanId);
    }

    return actualizada;
  }

  async reasignarOperarioTareaBorrador(payload: unknown) {
    const dto = ReasignarOperarioBorradorDTO.parse(payload);
    const modoAplicacion = dto.modoAplicacion ??
      (dto.aplicarADefinicion ? "TAMBIEN_DEFINICION" : "SOLO_TAREA");
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      select: {
        id: true,
        conjuntoId: true,
        borrador: true,
        tipo: true,
        fechaInicio: true,
        fechaFin: true,
        descripcion: true,
        ubicacionId: true,
        elementoId: true,
        frecuencia: true,
        supervisorId: true,
        periodoAnio: true,
        periodoMes: true,
      },
    });

    if (
      !tarea ||
      tarea.conjuntoId !== dto.conjuntoId ||
      !tarea.borrador ||
      tarea.tipo !== TipoTarea.PREVENTIVA
    ) {
      throw new Error("No es una tarea preventiva válida del borrador.");
    }

    let tareasObjetivo: Array<{
      id: number;
      fechaInicio: Date;
      fechaFin: Date;
    }> = [
      {
        id: tarea.id,
        fechaInicio: tarea.fechaInicio,
        fechaFin: tarea.fechaFin,
      },
    ];

    if (modoAplicacion !== "SOLO_TAREA") {
      const relacionadas = await this.prisma.tarea.findMany({
        where: {
          conjuntoId: dto.conjuntoId,
          borrador: true,
          tipo: TipoTarea.PREVENTIVA,
          periodoAnio:
            tarea.periodoAnio ?? tarea.fechaInicio.getFullYear(),
          periodoMes: tarea.periodoMes ?? tarea.fechaInicio.getMonth() + 1,
          descripcion: tarea.descripcion,
          ubicacionId: tarea.ubicacionId,
          elementoId: tarea.elementoId,
          ...(tarea.frecuencia == null ? {} : { frecuencia: tarea.frecuencia }),
          ...(tarea.supervisorId == null
            ? {}
            : { supervisorId: tarea.supervisorId }),
        },
        select: { id: true, fechaInicio: true, fechaFin: true },
        orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
      });
      if (relacionadas.length > 0) {
        tareasObjetivo = relacionadas;
      }
    }

    let tareaActualizada: Awaited<ReturnType<typeof this.editarBloqueBorrador>> | null = null;
    for (const tareaObjetivo of tareasObjetivo) {
      const actualizada = await this.editarBloqueBorrador(
        dto.conjuntoId,
        tareaObjetivo.id,
        {
          fechaInicio: tareaObjetivo.fechaInicio,
          fechaFin: tareaObjetivo.fechaFin,
          operariosIds: [dto.nuevoOperarioId],
        },
      );
      if (tareaObjetivo.id === dto.tareaId) {
        tareaActualizada = actualizada;
      }

      await this.auditarTarea({
        tareaId: tareaObjetivo.id,
        conjuntoId: dto.conjuntoId,
        accion: AccionAuditoria.REASIGNAR_OPERARIO,
        descripcion: `Se reasigno la tarea '${tarea.descripcion}' al operario ${dto.nuevoOperarioId}.`,
        periodoAnio: tarea.periodoAnio,
        periodoMes: tarea.periodoMes,
        metadataJson: {
          nuevoOperarioId: dto.nuevoOperarioId,
          modoAplicacion,
        },
      });
    }

    let definicionActualizada = false;
    let definicionId: number | null = null;
    let warning: string | null = null;

    if (modoAplicacion === "TAMBIEN_DEFINICION") {
      const candidatas = await this.prisma.definicionTareaPreventiva.findMany({
        where: {
          conjuntoId: dto.conjuntoId,
          descripcion: tarea.descripcion,
          ubicacionId: tarea.ubicacionId,
          elementoId: tarea.elementoId,
          ...(tarea.frecuencia == null ? {} : { frecuencia: tarea.frecuencia }),
          ...(tarea.supervisorId == null ? {} : { supervisorId: tarea.supervisorId }),
        },
        select: { id: true },
        orderBy: { id: "asc" },
        take: 2,
      });

      if (candidatas.length === 1) {
        definicionId = candidatas[0].id;
        await this.actualizar(dto.conjuntoId, definicionId, {
          operariosIds: [dto.nuevoOperarioId],
        });
        definicionActualizada = true;
      } else if (candidatas.length === 0) {
        warning =
          "Se actualizó el borrador, pero no se encontró una definición única para aplicar el cambio definitivo.";
      } else {
        warning =
          "Se actualizó el borrador, pero hubo varias definiciones candidatas y no se cambió la definición base.";
      }
    }

    return {
      ok: true,
      tarea: tareaActualizada,
      tareasActualizadas: tareasObjetivo.length,
      modoAplicacion,
      definicionActualizada,
      definicionId,
      warning,
    };
  }

  async reasignarOperarioExcluidaBorrador(payload: unknown) {
    const dto = ReasignarOperarioExcluidaDTO.parse(payload);
    const modoAplicacion = dto.modoAplicacion ??
      (dto.aplicarADefinicion ? "TAMBIEN_DEFINICION" : "SOLO_TAREA");
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
      select: {
        id: true,
        conjuntoId: true,
        estado: true,
        fechaObjetivo: true,
        defId: true,
        periodoAnio: true,
        periodoMes: true,
      },
    });

    if (!excluida || excluida.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }
    if (excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida ya no se puede editar.");
    }

    const nuevoOperarioId = dto.nuevoOperarioId.toString();
    const disponibilidad = await validarOperariosDisponiblesEnFecha({
      prisma: this.prisma,
      fecha: excluida.fechaObjetivo,
      operariosIds: [nuevoOperarioId],
    });
    if (!disponibilidad.ok) {
      throw new Error(
        `El operario ${disponibilidad.noDisponibles.join(", ")} no tiene disponibilidad para la fecha objetivo de esta excluida.`,
      );
    }

    const nombreOperario = await getOperarioNombre(this.prisma, nuevoOperarioId);
    let excluidasObjetivo = [dto.excluidaId];
    if (modoAplicacion !== "SOLO_TAREA" && excluida.defId != null) {
      const relacionadas = await this.prisma.preventivaExcluidaBorrador.findMany({
        where: {
          conjuntoId: dto.conjuntoId,
          estado: "PENDIENTE",
          defId: excluida.defId,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
        },
        select: { id: true },
        orderBy: [{ fechaObjetivo: "asc" }, { id: "asc" }],
      });
      if (relacionadas.length > 0) {
        excluidasObjetivo = relacionadas.map((item) => item.id);
      }
    }

    await this.prisma.preventivaExcluidaBorrador.updateMany({
      where: { id: { in: excluidasObjetivo } },
      data: {
        operariosIds: [nuevoOperarioId],
        operariosNombres: nombreOperario ? [nombreOperario] : [],
      },
    });
    const excluidaActualizada = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
    });

    let definicionActualizada = false;
    let warning: string | null = null;

    if (modoAplicacion === "TAMBIEN_DEFINICION") {
      if (excluida.defId != null) {
        await this.actualizar(dto.conjuntoId, excluida.defId, {
          operariosIds: [dto.nuevoOperarioId],
        });
        definicionActualizada = true;
      } else {
        warning =
          "Se actualizó la excluida, pero no se encontró la definición base para aplicar el cambio definitivo.";
      }
    }

    await this.registrarEventoBorrador({
      conjuntoId: dto.conjuntoId,
      periodoAnio: excluida.periodoAnio,
      periodoMes: excluida.periodoMes,
      tipo: "EXCLUIDA_REASIGNADA",
      accionAuditoria: AccionAuditoria.REASIGNAR_OPERARIO,
      excluidaId: excluida.id,
        detalle: `Se reasignó el operario de la tarea excluida al operario ${nombreOperario || nuevoOperarioId}.`,
        metadataJson: {
          nuevoOperarioId,
          nuevoOperarioNombre: nombreOperario,
          modoAplicacion,
          aplicarADefinicion: modoAplicacion === "TAMBIEN_DEFINICION",
          excluidasActualizadas: excluidasObjetivo.length,
        },
      });

    return {
      ok: true,
      excluida: excluidaActualizada,
      excluidasActualizadas: excluidasObjetivo.length,
      modoAplicacion,
      definicionActualizada,
      warning,
    };
  }

  async dividirExcluidaManual(payload: unknown) {
    const dto = DividirExcluidaManualDTO.parse(payload);
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
      select: {
        id: true,
        conjuntoId: true,
        estado: true,
        duracionMinutos: true,
        metadataJson: true,
        periodoAnio: true,
        periodoMes: true,
        descripcion: true,
      },
    });
    if (!excluida || excluida.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }
    if (excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida ya no se puede dividir manualmente.");
    }

    const actual = this.leerDivisionManualExcluida(excluida.metadataJson);
    if (actual?.bloques.some((bloque) => bloque.estado === "AGENDADO")) {
      throw new Error(
        "La tarea ya tiene bloques agendados. No puedes redefinir la división manual en este momento.",
      );
    }

    const total = dto.bloques.reduce((acc, bloque) => acc + bloque.duracionMinutos, 0);
    if (Math.abs(total - excluida.duracionMinutos) > 1) {
      throw new Error("La suma de minutos de los bloques debe coincidir con la duración total de la tarea excluida.");
    }

    const bloquesNormalizados = dto.bloques.map((bloque) => ({ ...bloque }));
    const diff = excluida.duracionMinutos - total;
    if (diff !== 0) {
      const ultimo = bloquesNormalizados[bloquesNormalizados.length - 1];
      ultimo.duracionMinutos += diff;
      if (ultimo.duracionMinutos <= 0) {
        throw new Error("La suma de minutos de los bloques no permite ajustar correctamente la duración final.");
      }
    }

    const division: DivisionManualExcluida = {
      activa: true,
      actualizadaEn: new Date().toISOString(),
      bloques: bloquesNormalizados.map((bloque, index) => ({
        id: `b${index + 1}`,
        orden: index + 1,
        duracionMinutos: bloque.duracionMinutos,
        estado: "PENDIENTE",
        tareaProgramadaId: null,
        fechaInicio: null,
        fechaFin: null,
      })),
    };

    const actualizada = await this.prisma.preventivaExcluidaBorrador.update({
      where: { id: excluida.id },
      data: {
        metadataJson: this.construirMetadataConDivisionManual(excluida.metadataJson, division),
      },
    });

    await this.registrarEventoBorrador({
      conjuntoId: dto.conjuntoId,
      periodoAnio: excluida.periodoAnio,
      periodoMes: excluida.periodoMes,
      tipo: "EXCLUIDA_DIVIDIDA_MANUAL",
      accionAuditoria: AccionAuditoria.DIVIDIR,
      excluidaId: excluida.id,
      detalle: `Se dividió manualmente la tarea excluida '${excluida.descripcion}' en ${division.bloques.length} bloque(s).`,
      metadataJson: {
        bloques: division.bloques.map((bloque) => ({
          id: bloque.id,
          orden: bloque.orden,
          duracionMinutos: bloque.duracionMinutos,
        })),
      },
    });

    return { ok: true, excluida: actualizada };
  }

  async sugerirHuecosBloqueExcluida(payload: unknown) {
    const dto = GestionarBloqueExcluidaDTO.parse(payload);
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
    });
    if (!excluida || excluida.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }

    const division = this.leerDivisionManualExcluida(excluida.metadataJson);
    const bloque = this.resolverBloqueDivision(division, dto.bloqueId);
    if (!bloque) {
      throw new Error("El bloque solicitado no existe en la división manual de la excluida.");
    }
    if (bloque.estado === "AGENDADO") {
      throw new Error("Ese bloque ya fue agendado.");
    }

    return this.sugerirHuecosParaExcluidaCore({
      conjuntoId: dto.conjuntoId,
      excluida: {
        id: excluida.id,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        descripcion: `${excluida.descripcion} · Bloque ${bloque.orden}`,
        duracionMinutos: bloque.duracionMinutos,
        fechaObjetivo: excluida.fechaObjetivo,
        operariosIds: excluida.operariosIds,
      },
      fechaPreferida: dto.fechaInicio ?? excluida.fechaObjetivo,
      maxOpciones: 8,
      permitirSplitMismoDia: false,
      permitirDivisionFlexible: false,
    });
  }

  async agendarBloqueExcluida(payload: unknown) {
    const dto = GestionarBloqueExcluidaDTO.parse(payload);
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
    });
    if (!excluida || excluida.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }

    const division = this.leerDivisionManualExcluida(excluida.metadataJson);
    const bloque = this.resolverBloqueDivision(division, dto.bloqueId);
    if (!division || !bloque) {
      throw new Error("La excluida no tiene una división manual válida para este bloque.");
    }
    if (bloque.estado === "AGENDADO") {
      throw new Error("Ese bloque ya fue agendado.");
    }

    let fechaInicio = dto.fechaInicio ?? null;
    let fechaFin = dto.fechaFin ?? null;
    if (!fechaInicio || !fechaFin) {
      const sugerencias = await this.sugerirHuecosBloqueExcluida({
        conjuntoId: dto.conjuntoId,
        excluidaId: dto.excluidaId,
        bloqueId: dto.bloqueId,
        fechaInicio: dto.fechaInicio,
      });
      const sugerida = sugerencias.opciones[0];
      if (!sugerida) {
        throw new Error("No se encontraron huecos disponibles para este bloque.");
      }
      fechaInicio = new Date(sugerida.fechaInicio);
      fechaFin = new Date(sugerida.fechaFin);
    }

    await this.validarSlotPreventivaBorrador({
      conjuntoId: dto.conjuntoId,
      fechaInicio,
      fechaFin,
      operariosIds: excluida.operariosIds,
      identidad: this.identidadDeExcluida(excluida),
    });

    const grupoPlanId = `EXC-MANUAL-${excluida.id}`;
    const necesidadesIds = await this.necesidadesIdsDeDefId(excluida.defId);
    const tarea = await this.prisma.$transaction(async (tx) => {
      const creada = await tx.tarea.create({
        data: {
          descripcion: `${excluida.descripcion} · Bloque ${bloque.orden}`,
          fechaInicio,
          fechaFin,
          duracionMinutos: Math.max(
            1,
            Math.round((fechaFin.getTime() - fechaInicio.getTime()) / 60000),
          ),
          prioridad: excluida.prioridad,
          estado: EstadoTarea.ASIGNADA,
          tipo: TipoTarea.PREVENTIVA,
          frecuencia: excluida.frecuencia,
          definicionId: excluida.defId,
          diaSemanaProgramado: excluida.diaSemanaProgramado,
          borrador: true,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          grupoPlanId,
          bloqueIndex: bloque.orden,
          bloquesTotales: division.bloques.length,
          ubicacionId: excluida.ubicacionId,
          elementoId: excluida.elementoId,
          conjuntoId: dto.conjuntoId,
          supervisorId: excluida.supervisorId,
          operarios: excluida.operariosIds.length
            ? { connect: excluida.operariosIds.map((id) => ({ id })) }
            : undefined,
          necesidades: necesidadesIds.length
            ? { connect: necesidadesIds.map((id) => ({ id })) }
            : undefined,
        },
      });

      const nuevaDivision: DivisionManualExcluida = {
        ...division,
        actualizadaEn: new Date().toISOString(),
        bloques: division.bloques.map((item) =>
          item.id === dto.bloqueId
            ? {
                ...item,
                estado: "AGENDADO",
                tareaProgramadaId: creada.id,
                fechaInicio: fechaInicio.toISOString(),
                fechaFin: fechaFin.toISOString(),
              }
            : item,
        ),
      };
      const todosAgendados = nuevaDivision.bloques.every((item) => item.estado === "AGENDADO");

      await tx.preventivaExcluidaBorrador.update({
        where: { id: excluida.id },
        data: {
          estado: todosAgendados ? "AGENDADA" : excluida.estado,
          tareaProgramadaId: creada.id,
          resueltaEn: todosAgendados ? new Date() : null,
          metadataJson: this.construirMetadataConDivisionManual(excluida.metadataJson, nuevaDivision),
        },
      });

      await tx.preventivaBorradorEvento.create({
        data: {
          conjuntoId: dto.conjuntoId,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          tipo: "EXCLUIDA_BLOQUE_AGENDADO",
          excluidaId: excluida.id,
          tareaId: creada.id,
          detalle: `Se agendó el bloque ${bloque.orden} de la tarea excluida '${excluida.descripcion}'.`,
          actorId: this.actor?.id ?? null,
          actorRol: this.actor?.rol ?? null,
          metadataJson: {
            bloqueId: bloque.id,
            orden: bloque.orden,
            fechaInicio: fechaInicio.toISOString(),
            fechaFin: fechaFin.toISOString(),
            completaExcluida: todosAgendados,
          },
        },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.EXCLUIDA,
        entidad: EntidadAuditoria.EXCLUIDA_BORRADOR,
        entidadId: excluida.id,
        accion: AccionAuditoria.AGENDAR_EXCLUIDA,
        conjuntoId: dto.conjuntoId,
        actor: this.actor,
        descripcion: `Se agendo el bloque ${bloque.orden} de la tarea excluida '${excluida.descripcion}'.`,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        metadataJson: {
          tareaId: creada.id,
          bloqueId: bloque.id,
          orden: bloque.orden,
          fechaInicio: fechaInicio.toISOString(),
          fechaFin: fechaFin.toISOString(),
          completaExcluida: todosAgendados,
        },
      });

      return creada;
    });

    return { ok: true, tarea };
  }

  async reordenarTareasBorradorDia(payload: unknown) {
    const dto = ReordenarTareasDiaBorradorDTO.parse(payload);
    const inicioDia = new Date(
      dto.fecha.getFullYear(),
      dto.fecha.getMonth(),
      dto.fecha.getDate(),
      0,
      0,
      0,
      0,
    );
    const finDia = new Date(
      dto.fecha.getFullYear(),
      dto.fecha.getMonth(),
      dto.fecha.getDate(),
      23,
      59,
      59,
      999,
    );

    const tareasDiaDisponibles = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: dto.conjuntoId,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
        estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
        NOT: {
          estado: "NO_COMPLETADA" as any,
          reprogramada: true,
          reprogramadaPorTareaId: { not: null },
        },
        fechaInicio: { gte: inicioDia, lte: finDia },
      },
      include: {
        operarios: {
          select: {
            id: true,
            usuario: { select: { nombre: true } },
          },
        },
        necesidades: { select: { id: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    const tareasPorId = new Map(
      tareasDiaDisponibles.map((tarea) => [tarea.id, tarea]),
    );
    const idsSolicitados = new Set(dto.tareaIds);
    if (
      idsSolicitados.size !== dto.tareaIds.length ||
      dto.tareaIds.some((id) => !tareasPorId.has(id))
    ) {
      throw new Error("Algunas tareas no pertenecen a ese día del borrador o no son válidas.");
    }

    const horarioDia = await this.prisma.conjuntoHorario.findFirst({
      where: { conjuntoId: dto.conjuntoId, dia: dateToDiaSemana(dto.fecha) },
      select: {
        horaApertura: true,
        horaCierre: true,
        descansoInicio: true,
        descansoFin: true,
      },
    });

    if (!horarioDia) {
      throw new Error("No hay horario configurado para ese día en el conjunto.");
    }

    const horario: HorarioDia = {
      startMin: toMin(horarioDia.horaApertura),
      endMin: toMin(horarioDia.horaCierre),
      descansoStartMin: horarioDia.descansoInicio
        ? toMin(horarioDia.descansoInicio)
        : undefined,
      descansoEndMin: horarioDia.descansoFin ? toMin(horarioDia.descansoFin) : undefined,
    };
    // Un "bloque" nunca se reordena solo cuando es parte de una tarea dividida
    // ese mismo día: todos sus tramos forman una unidad y se recalculan juntos
    // (se pueden volver a unir o a partir alrededor del almuerzo). Antes solo
    // el par pegado al almuerzo era unidad y cualquier otra división quedaba
    // con tramos sueltos de tamaño desactualizado. Los tramos de otros días
    // del mismo grupo no entran. Si los tramos tienen operarios/plazas
    // distintos no se pueden fusionar: solo el par del almuerzo sigue siendo
    // unidad (el caso conocido), el resto se mueve tramo por tramo.
    const bloquesPorGrupo = new Map<string, typeof tareasDiaDisponibles>();
    for (const tarea of tareasDiaDisponibles) {
      if (!tarea.grupoPlanId) continue;
      const bloques = bloquesPorGrupo.get(tarea.grupoPlanId) ?? [];
      bloques.push(tarea);
      bloquesPorGrupo.set(tarea.grupoPlanId, bloques);
    }
    const firmaAsignacion = (t: (typeof tareasDiaDisponibles)[number]) =>
      t.operarios.map((o) => o.id).sort().join("|") +
      "#" +
      (t.necesidades ?? []).map((n) => n.id).sort().join("|");
    const parejaPorId = new Map<number, typeof tareasDiaDisponibles>();
    for (const bloquesGrupo of bloquesPorGrupo.values()) {
      if (bloquesGrupo.length < 2) continue;
      const bloques = [...bloquesGrupo].sort(
        (a, b) => +a.fechaInicio - +b.fechaInicio || a.id - b.id,
      );
      const esParAlmuerzo =
        bloques.length === 2 &&
        horario.descansoStartMin != null &&
        horario.descansoEndMin != null &&
        toMinOfDaySafe(bloques[0].fechaFin) === horario.descansoStartMin &&
        toMinOfDaySafe(bloques[1].fechaInicio) === horario.descansoEndMin;
      const mismaAsignacion = bloques.every(
        (b) => firmaAsignacion(b) === firmaAsignacion(bloques[0]),
      );
      if (!esParAlmuerzo && !mismaAsignacion) continue;
      for (const bloque of bloques) parejaPorId.set(bloque.id, bloques);
    }
    // Se incluyen ambos tramos aunque la vista filtrada solo haya enviado uno.
    const idsInvolucrados = new Set(idsSolicitados);
    for (const id of idsSolicitados) {
      for (const tramo of parejaPorId.get(id) ?? []) idsInvolucrados.add(tramo.id);
    }
    const tareasInvolucradas = tareasDiaDisponibles.filter((tarea) =>
      idsInvolucrados.has(tarea.id),
    );
    const seleccionOrdenada: Array<typeof tareasDiaDisponibles> = [];
    const unidadesAgregadas = new Set<number>();
    for (const id of dto.tareaIds) {
      const unidad = parejaPorId.get(id) ?? [tareasPorId.get(id)!];
      if (unidadesAgregadas.has(unidad[0].id)) continue;
      seleccionOrdenada.push(unidad);
      unidadesAgregadas.add(unidad[0].id);
    }
    const ventanasTrabajo = construirVentanasTrabajoDia(horario);
    const ventanasReordenamiento = construirVentanasOcupadasReordenamiento({
      tareas: tareasInvolucradas,
      ventanasTrabajo,
    });
    const primeraVentana = ventanasReordenamiento[0] ?? ventanasTrabajo[0];
    if (!primeraVentana) {
      throw new Error("No hay ventanas disponibles para reordenar las tareas del día.");
    }

    const actualizaciones: Array<{ id: number; fechaInicio: Date; fechaFin: Date; duracionMinutos: number }> = [];
    const recreaciones: Array<{
      originales: typeof tareasInvolucradas;
      segmentos: Array<{ fechaInicio: Date; fechaFin: Date }>;
    }> = [];
    const nombresOperariosInvolucrados = Array.from(
      new Set(
        tareasInvolucradas.flatMap((tarea) =>
          tarea.operarios.map(
            (operario) =>
              operario.usuario?.nombre?.trim() || `Operario ${operario.id}`,
          ),
        ),
      ),
    );
    const contextoInvolucrados = nombresOperariosInvolucrados.length
      ? ` Operarios involucrados: ${nombresOperariosInvolucrados.join(", ")}.`
      : "";

    // ── Cascada de ajustes ──────────────────────────────────────────────
    // Si el nuevo horario de una tarea solicitada choca con una tarea ajena
    // (de otro operario), en vez de rechazar el reordenamiento se intenta
    // primero correr esa tarea ajena al siguiente hueco libre de ESE MISMO
    // día para sus propios operarios. Solo si de verdad no hay hueco se
    // marca para excluir. `agendaCascada` es una copia en memoria de la
    // agenda del día que se va actualizando con cada tarea recolocada
    // (tanto las solicitadas como las de la cascada) para que la búsqueda
    // del siguiente hueco sea siempre consistente con lo ya decidido.
    type CambioCascada = {
      tareaId: number;
      descripcion: string;
      operariosNombres: string[];
      accion: "MOVIDA" | "EXCLUIDA";
      fechaInicioOriginal: Date;
      fechaFinOriginal: Date;
      fechaInicioNueva?: Date;
      fechaFinNueva?: Date;
      motivo: string;
    };
    const operariosIdsDelDia = Array.from(
      new Set(
        tareasDiaDisponibles.flatMap((t) => t.operarios.map((o) => o.id)),
      ),
    );
    const agendaCascada = operariosIdsDelDia.length
      ? await buildAgendaPorOperarioDia({
          prisma: this.prisma,
          conjuntoId: dto.conjuntoId,
          fechaDia: dto.fecha,
          operariosIds: operariosIdsDelDia,
          incluirBorrador: true,
          bloqueosGlobales: buildBloqueosPorDescanso(horario),
          excluirEstados: ["PENDIENTE_REPROGRAMACION"],
          excluirTareaIds: Array.from(idsInvolucrados),
        })
      : {};
    const marcarOcupadoEnCascada = (
      operariosIdsTarea: string[],
      intervalos: Array<{ i: number; f: number }>,
    ) => {
      for (const opId of operariosIdsTarea) {
        agendaCascada[opId] = mergeIntervalos([
          ...(agendaCascada[opId] ?? []),
          ...intervalos,
        ]);
      }
    };
    const cambiosCascada: CambioCascada[] = [];
    const idsResueltosCascada = new Set<number>();
    const replanificarPareja = Symbol("replanificarPareja");
    let parejaQueBloquea: typeof tareasDiaDisponibles | null = null;

    // No hace falta recursión explícita para "si mover B choca con C,
    // reubicar C también": `buscarHuecoDiaEarliest` ya busca contra
    // `agendaCascada`, que en todo momento refleja TODAS las tareas del día
    // ya resueltas (las solicitadas y las de la cascada). El hueco que
    // encuentra ya está garantizado libre frente a todo lo decidido hasta
    // ahora, así que una sola búsqueda por bloqueadora es suficiente.
    const intentarResolverBloqueadora = async (
      tareaBloqueadoraId: number,
    ): Promise<void> => {
      if (idsResueltosCascada.has(tareaBloqueadoraId)) return;
      idsResueltosCascada.add(tareaBloqueadoraId);

      const bloqueadora = await this.prisma.tarea.findUnique({
        where: { id: tareaBloqueadoraId },
        include: {
          operarios: { include: { usuario: { select: { nombre: true } } } },
        },
      });
      if (!bloqueadora) return;

      // Un tramo que rodea el almuerzo obliga a recalcular ambos tramos.
      // Se reinicia la planificación incluyendo la pareja, sin escribir aún.
      const pareja = parejaPorId.get(bloqueadora.id);
      if (pareja) {
        parejaQueBloquea = pareja;
        throw replanificarPareja;
      }
      const operariosIdsBloqueadora = bloqueadora.operarios.map((o) => o.id);
      const nombresBloqueadora = bloqueadora.operarios.map(
        (o) => o.usuario?.nombre?.trim() || `Operario ${o.id}`,
      );
      const duracion = Math.max(1, bloqueadora.duracionMinutos);

      // Una tarea con varios bloques el mismo día (que no sea la pareja del
      // almuerzo) no se reubica por separado: en vez de abortar todo el
      // reordenamiento, se propone excluirla y el usuario decide.
      const variosBloquesEnElDia =
        !!bloqueadora.grupoPlanId &&
        (bloquesPorGrupo.get(bloqueadora.grupoPlanId)?.length ?? 0) > 1;

      // Primero busca hueco desde su hora original; si no hay, desde la
      // apertura (puede haber un hueco libre más temprano ese mismo día).
      const nuevoInicioMin = variosBloquesEnElDia
        ? null
        : (buscarHuecoDiaEarliest({
            startMin: horario.startMin,
            endMin: horario.endMin,
            durMin: duracion,
            operariosIds: operariosIdsBloqueadora,
            agendaPorOperario: agendaCascada,
            desiredStartMin: toMinOfDaySafe(bloqueadora.fechaInicio),
          }) ??
          buscarHuecoDiaEarliest({
            startMin: horario.startMin,
            endMin: horario.endMin,
            durMin: duracion,
            operariosIds: operariosIdsBloqueadora,
            agendaPorOperario: agendaCascada,
            desiredStartMin: horario.startMin,
          }));

      if (nuevoInicioMin != null) {
        const fechaInicioNueva = toDateAtMin(dto.fecha, nuevoInicioMin);
        const fechaFinNueva = toDateAtMin(dto.fecha, nuevoInicioMin + duracion);
        marcarOcupadoEnCascada(operariosIdsBloqueadora, [
          { i: nuevoInicioMin, f: nuevoInicioMin + duracion },
        ]);
        cambiosCascada.push({
          tareaId: bloqueadora.id,
          descripcion: bloqueadora.descripcion,
          operariosNombres: nombresBloqueadora,
          accion: "MOVIDA",
          fechaInicioOriginal: bloqueadora.fechaInicio,
          fechaFinOriginal: bloqueadora.fechaFin,
          fechaInicioNueva,
          fechaFinNueva,
          motivo: "Se reacomodó ese mismo día para dejar espacio al nuevo orden.",
        });
        return;
      }

      cambiosCascada.push({
        tareaId: bloqueadora.id,
        descripcion: bloqueadora.descripcion,
        operariosNombres: nombresBloqueadora,
        accion: "EXCLUIDA",
        fechaInicioOriginal: bloqueadora.fechaInicio,
        fechaFinOriginal: bloqueadora.fechaFin,
        motivo:
          `No quedó un hueco libre ese día para reacomodar "${bloqueadora.descripcion}" ` +
          `(estaba de ${formatHoraLocal(bloqueadora.fechaInicio)} a ` +
          `${formatHoraLocal(bloqueadora.fechaFin)} el ${formatFechaLocal(bloqueadora.fechaInicio)}) ` +
          "tras el nuevo orden.",
      });
    };

    // Cada operario lleva su propio cursor: las tareas de operarios distintos
    // siguen siendo paralelas. Antes todas se apilaban en una sola línea de
    // tiempo y la suma de duraciones superaba la jornada ("no cabe").
    const SIN_OPERARIO = "__sin_operario__";
    const cursoresMin = new Map<string, number>();
    const idsOperariosDeUnidad = (unidad: typeof tareasDiaDisponibles) => {
      const ids = Array.from(
        new Set(unidad.flatMap((bloque) => bloque.operarios.map((o) => o.id))),
      );
      return ids.length ? ids : [SIN_OPERARIO];
    };

    // Si una tarea no cabe (ni en las ventanas ocupadas ni en toda la
    // jornada) se propone excluirla en lugar de abortar el reordenamiento:
    // se respeta el orden pedido y solo lo que desborda queda como candidato,
    // que el usuario debe confirmar.
    const proponerExclusionPorFaltaDeEspacio = (
      unidad: typeof tareasDiaDisponibles,
      detalle: string,
    ) => {
      for (const bloque of unidad) {
        cambiosCascada.push({
          tareaId: bloque.id,
          descripcion: bloque.descripcion,
          operariosNombres: bloque.operarios.map(
            (o) => o.usuario?.nombre?.trim() || `Operario ${o.id}`,
          ),
          accion: "EXCLUIDA",
          fechaInicioOriginal: bloque.fechaInicio,
          fechaFinOriginal: bloque.fechaFin,
          motivo:
            `Con el nuevo orden no queda espacio ese día para "${bloque.descripcion}" ` +
            `(estaba de ${formatHoraLocal(bloque.fechaInicio)} a ` +
            `${formatHoraLocal(bloque.fechaFin)}). ${detalle}`,
        });
      }
    };

    // Calcula (sin escribir nada) dónde caería una unidad con los cursores
    // actuales de sus operarios. Lanza MENSAJE_REORDEN_NO_CABE si no cabe.
    const planificarUnidad = (unidad: typeof tareasDiaDisponibles) => {
      const duracion = unidad.reduce(
        (total, bloque) => total + calcularDuracionLaboralReordenamiento({ tarea: bloque, horario }),
        0,
      );
      const operariosUnidad = idsOperariosDeUnidad(unidad);
      const cursorUnidadMin = Math.max(
        ...operariosUnidad.map((id) => cursoresMin.get(id) ?? primeraVentana.i),
      );
      // Ventanas ocupadas solo por las tareas de los mismos operarios.
      const ventanasUnidad = construirVentanasOcupadasReordenamiento({
        tareas: tareasInvolucradas.filter((otra) =>
          idsOperariosDeUnidad([otra]).some((id) => operariosUnidad.includes(id)),
        ),
        ventanasTrabajo,
      });
      const cursor = toDateAtMin(dto.fecha, cursorUnidadMin);
      const segmentos =
        intentarDistribuirDuracionReordenamiento({
          fecha: dto.fecha,
          ventanas: ventanasUnidad,
          inicioCursor: cursor,
          duracionMinutos: duracion,
          horario,
        }) ??
        distribuirDuracionReordenamiento({
          fecha: dto.fecha,
          ventanas: ventanasTrabajo,
          inicioCursor: cursor,
          duracionMinutos: duracion,
          horario,
        });
      return { segmentos, operariosUnidad, duracion };
    };
    try {
    for (const originales of seleccionOrdenada) {
      const tarea = originales[0];
      const operariosUnidad = idsOperariosDeUnidad(originales);

      let segmentos: Array<{ fechaInicio: Date; fechaFin: Date }>;
      try {
        segmentos = planificarUnidad(originales).segmentos;
      } catch (error) {
        const detalle = error instanceof Error ? error.message : String(error);
        if (detalle === MENSAJE_REORDEN_NO_CABE) {
          proponerExclusionPorFaltaDeEspacio(
            originales,
            "Las tareas de ese operario ya ocupan toda la jornada.",
          );
          continue;
        }
        throw new Error(
          `No se pudo aplicar el nuevo orden al llegar a la tarea "${tarea.descripcion}". ` +
          `${detalle}${contextoInvolucrados}`,
        );
      }

      const fechaInicio = segmentos[0]?.fechaInicio;
      const fechaFin = segmentos[segmentos.length - 1]?.fechaFin;

      if (!fechaInicio || !fechaFin) {
        throw new Error("No se pudo calcular la nueva programación de una tarea.");
      }

      for (const segmento of segmentos) {
        await this.validarHorarioBloqueBorrador({
          conjuntoId: dto.conjuntoId,
          fechaInicio: segmento.fechaInicio,
          fechaFin: segmento.fechaFin,
        });
      }

      const inicioEsFestivo = await isFestivoDate({
        prisma: this.prisma,
        fecha: fechaInicio,
        pais: "CO",
      });
      if (inicioEsFestivo) {
        // El reordenamiento no cambia operarios/plaza: si ya trabajaban ese
        // festivo (ver operariosPuedenTrabajarFestivo), lo siguen haciendo.
        const operariosDeTarea = tarea.operarios.map((o) => o.id);
        const puedenTrabajarFestivo =
          operariosDeTarea.length > 0 &&
          (await operariosPuedenTrabajarFestivo({
            prisma: this.prisma,
            conjuntoId: dto.conjuntoId,
            operariosIds: operariosDeTarea,
          }));
        if (!puedenTrabajarFestivo) {
          throw new Error("No se permite programar tareas preventivas en festivos.");
        }
      }

      const operariosPorSegmento = segmentos.map((_, index) =>
        originales[Math.min(index, originales.length - 1)].operarios.map((item) => item.id),
      );
      if (originales.length >= 2 && segmentos.length < originales.length) {
        const mismaAsignacionUnidad = originales.every(
          (bloque) => firmaAsignacion(bloque) === firmaAsignacion(originales[0]),
        );
        if (!mismaAsignacionUnidad) {
          throw new Error(
            `No se puede unir la tarea "${tarea.descripcion}" porque sus bloques tienen asignaciones distintas.`,
          );
        }
      }
      const operariosIds = Array.from(new Set(operariosPorSegmento.flat()));

      let fueraDeJornadaOperario: string | null = null;
      for (const [index, segmento] of segmentos.entries()) {
        const validacion = await validarIntervaloProgramacion({
          prisma: this.prisma,
          conjuntoId: dto.conjuntoId,
          fechaInicio: segmento.fechaInicio,
          fechaFin: segmento.fechaFin,
          operariosIds: operariosPorSegmento[index],
        });
        if (!validacion.ok) {
          // Quedar fuera de la jornada del operario/conjunto equivale a "no
          // cabe": se propone excluir. Otros motivos siguen siendo error.
          if (
            validacion.motivo === "FUERA_HORARIO_OPERARIO" ||
            validacion.motivo === "FUERA_HORARIO_CONJUNTO"
          ) {
            fueraDeJornadaOperario = validacion.mensaje;
            break;
          }
          throw new Error(
            `No se pudo ubicar la tarea "${tarea.descripcion}": ${validacion.mensaje}` +
              contextoInvolucrados,
          );
        }
      }
      if (fueraDeJornadaOperario) {
        proponerExclusionPorFaltaDeEspacio(originales, fueraDeJornadaOperario);
        continue;
      }

      // Se registra el nuevo horario de esta tarea en la agenda en memoria
      // ANTES de resolver sus propios solapes: si otra tarea choca contra
      // ESTE nuevo horario, la cascada debe verla como ocupada, no como
      // libre. Así también queda disponible para la tarea siguiente del
      // bucle y para cualquier cascada posterior.
      for (const [index, segmento] of segmentos.entries()) {
        marcarOcupadoEnCascada(operariosPorSegmento[index], [{
          i: toMinOfDaySafe(segmento.fechaInicio),
          f: toMinOfDaySafe(segmento.fechaFin),
        }]);
      }
      if (operariosIds.length) {
        const disponibilidad = await validarOperariosDisponiblesEnFecha({
          prisma: this.prisma,
          fecha: fechaInicio,
          operariosIds,
        });
        if (!disponibilidad.ok) {
          throw new Error(
            await construirMensajeSinDisponibilidadOperarios(
              this.prisma,
              disponibilidad.noDisponibles,
            ),
          );
        }

        for (const [index, segmento] of segmentos.entries()) {
          // Se repite hasta que ya no aparezca ninguna tarea ajena chocando
          // con este segmento: cada vuelta resuelve UNA bloqueadora (la
          // mueve o la marca para excluir) y la saca de la búsqueda, así
          // que el ciclo siempre termina. El tope es solo una salvaguarda.
          // Salvaguarda alta: un tope bajo dejaba solapes sin resolver en
          // silencio cuando un segmento chocaba con muchas tareas.
          let vueltas = 0;
          while (vueltas++ < 200) {
            const solape = await this.prisma.tarea.findFirst({
              where: {
                conjuntoId: dto.conjuntoId,
                borrador: true,
                id: {
                  notIn: [
                    ...Array.from(idsInvolucrados),
                    ...Array.from(idsResueltosCascada),
                  ],
                },
                estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
                NOT: {
                  estado: "NO_COMPLETADA" as any,
                  reprogramada: true,
                  reprogramadaPorTareaId: { not: null },
                },
                fechaInicio: { lt: segmento.fechaFin },
                fechaFin: { gt: segmento.fechaInicio },
                operarios: { some: { id: { in: operariosPorSegmento[index] } } },
              },
              select: { id: true },
            });
            if (!solape) break;
            await intentarResolverBloqueadora(solape.id);
          }
        }
      }

      if (segmentos.length === originales.length) {
        for (const [index, segmento] of segmentos.entries()) {
          actualizaciones.push({
            id: originales[index].id,
            ...segmento,
            duracionMinutos: Math.round((+segmento.fechaFin - +segmento.fechaInicio) / 60000),
          });
        }
      } else {
        recreaciones.push({ originales, segmentos });
      }
      const finMin = toMinOfDaySafe(fechaFin);
      for (const id of operariosUnidad) cursoresMin.set(id, finMin);
    }
    } catch (error) {
      if (error !== replanificarPareja || !parejaQueBloquea) throw error;
      return this.reordenarTareasBorradorDia({
        ...dto,
        tareaIds: [...dto.tareaIds, ...parejaQueBloquea.map((bloque) => bloque.id)],
      });
    }

    const cambiosCascadaSerializados = cambiosCascada.map((cambio) => ({
      tareaId: cambio.tareaId,
      descripcion: cambio.descripcion,
      operariosNombres: cambio.operariosNombres,
      accion: cambio.accion,
      fechaInicioOriginal: cambio.fechaInicioOriginal.toISOString(),
      fechaFinOriginal: cambio.fechaFinOriginal.toISOString(),
      fechaInicioNueva: cambio.fechaInicioNueva?.toISOString() ?? null,
      fechaFinNueva: cambio.fechaFinNueva?.toISOString() ?? null,
      motivo: cambio.motivo,
    }));

    // La cascada puede necesitar excluir alguna tarea ajena para poder
    // aplicar el nuevo orden. Eso no se hace sin avisar: se devuelve la
    // vista previa completa (sin tocar la BD) y el frontend debe mostrarla
    // y pedir confirmación explícita antes de reintentar con
    // `confirmarExclusiones: true`.
    const hayExclusiones = cambiosCascada.some(
      (cambio) => cambio.accion === "EXCLUIDA",
    );
    if (hayExclusiones && !dto.confirmarExclusiones) {
      return {
        ok: true,
        requiereConfirmacion: true,
        aplicado: false,
        reordenadas: 0,
        divididas: 0,
        ajustadasPorDependencia: 0,
        omitidasPorDivisionAlmuerzo: 0,
        operariosInvolucrados: nombresOperariosInvolucrados,
        cambiosCascada: cambiosCascadaSerializados,
      };
    }

    await this.prisma.$transaction(async (tx) => {
      for (const item of actualizaciones) {
        await tx.tarea.update({
          where: { id: item.id },
          data: {
            fechaInicio: item.fechaInicio,
            fechaFin: item.fechaFin,
            duracionMinutos: item.duracionMinutos,
          },
        });
      }

      for (const cambio of cambiosCascada) {
        if (cambio.accion !== "MOVIDA") continue;
        await tx.tarea.update({
          where: { id: cambio.tareaId },
          data: {
            fechaInicio: cambio.fechaInicioNueva!,
            fechaFin: cambio.fechaFinNueva!,
          },
        });
      }

      const gruposAReindexar = new Set<string>();
      for (const item of recreaciones) {
        const original = item.originales[0];
        const grupoPlanId =
          original.grupoPlanId ??
          `REORD-${original.id}-${dayKey(dto.fecha)}-${randomUUID()}`;
        gruposAReindexar.add(grupoPlanId);
        const primero = item.segmentos[0];
        await tx.tarea.update({
          where: { id: original.id },
          data: {
            ...primero,
            duracionMinutos: Math.round((+primero.fechaFin - +primero.fechaInicio) / 60000),
            grupoPlanId,
            bloqueIndex: original.bloqueIndex ?? 1,
            bloquesTotales: item.segmentos.length,
          },
        });
        // Tramos restantes: se reutilizan los existentes, se crean los que
        // faltan y se borran los que sobran (p. ej. 3 bloques -> 1).
        const totalTramos = Math.max(item.segmentos.length, item.originales.length);
        for (let i = 1; i < totalTramos; i++) {
          const segmento = item.segmentos[i];
          const existente = item.originales[i];
          if (segmento && existente) {
            await tx.tarea.update({
              where: { id: existente.id },
              data: {
                ...segmento,
                duracionMinutos: Math.round((+segmento.fechaFin - +segmento.fechaInicio) / 60000),
                grupoPlanId,
                bloqueIndex: i + 1,
                bloquesTotales: item.segmentos.length,
              },
            });
          } else if (segmento) {
            await tx.tarea.create({
              data: {
                ...buildTareaBorradorCreateData(original, segmento.fechaInicio, segmento.fechaFin),
                grupoPlanId,
                bloqueIndex: i + 1,
                bloquesTotales: item.segmentos.length,
              },
            });
          } else if (existente) {
            await tx.usoMaquinaria.deleteMany({ where: { tareaId: { in: [existente.id] } } });
            await tx.tarea.delete({ where: { id: existente.id } });
          }
        }
      }
      for (const grupoPlanId of gruposAReindexar) {
        const bloques = await tx.tarea.findMany({
          where: { conjuntoId: dto.conjuntoId, borrador: true, grupoPlanId },
          select: { id: true, fechaInicio: true },
          orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
        for (const [index, bloque] of bloques.entries()) {
          await tx.tarea.update({
            where: { id: bloque.id },
            data: bloques.length === 1
              ? { grupoPlanId: null, bloqueIndex: null, bloquesTotales: null }
              : { bloqueIndex: index + 1, bloquesTotales: bloques.length },
          });
        }
      }
    });

    // Las exclusiones de la cascada se procesan después de la transacción
    // principal, con el mismo patrón secuencial (snapshot + borrar) que ya
    // usa `eliminarBloqueBorrador` para retirar una tarea del borrador.
    for (const cambio of cambiosCascada) {
      if (cambio.accion !== "EXCLUIDA") continue;
      await this.crearExcluidaDesdeTarea({
        tareaId: cambio.tareaId,
        motivoTipo: "REORDEN_MANUAL_SIN_HUECO",
        motivoMensaje: cambio.motivo,
      });
      await this.prisma.usoMaquinaria.deleteMany({
        where: { tareaId: { in: [cambio.tareaId] } },
      });
      await this.prisma.tarea.delete({ where: { id: cambio.tareaId } });
      const original = tareasPorId.get(cambio.tareaId);
      if (original?.grupoPlanId) {
        const restantes = await this.prisma.tarea.findMany({
          where: {
            conjuntoId: dto.conjuntoId,
            borrador: true,
            grupoPlanId: original.grupoPlanId,
          },
          select: { id: true },
          orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
        for (const [index, bloque] of restantes.entries()) {
          await this.prisma.tarea.update({
            where: { id: bloque.id },
            data: restantes.length === 1
              ? { grupoPlanId: null, bloqueIndex: null, bloquesTotales: null }
              : { bloqueIndex: index + 1, bloquesTotales: restantes.length },
          });
        }
      }
      if (original?.ocurrenciaPlanId) {
        await this.reconciliarOcurrenciaProgramada(original.ocurrenciaPlanId);
      }
    }

    const ocurrenciasAReconciliar = Array.from(
      new Set(
        tareasInvolucradas
          .map((tarea) => tarea.ocurrenciaPlanId)
          .filter((id): id is string => Boolean(id)),
      ),
    );
    for (const ocurrenciaPlanId of ocurrenciasAReconciliar) {
      await this.reconciliarOcurrenciaProgramada(ocurrenciaPlanId);
    }

    return {
      ok: true,
      requiereConfirmacion: false,
      aplicado: true,
      reordenadas: actualizaciones.length + recreaciones.length,
      divididas: recreaciones.filter(
        (item) => item.segmentos.length > item.originales.length,
      ).length,
      unidas: recreaciones.filter(
        (item) => item.segmentos.length < item.originales.length,
      ).length,
      // Ya no se amplía el conjunto por operario compartido, así que esto
      // siempre es 0; se conserva por compatibilidad con el frontend.
      ajustadasPorDependencia: 0,
      omitidasPorDivisionAlmuerzo: 0,
      operariosInvolucrados: nombresOperariosInvolucrados,
      cambiosCascada: cambiosCascadaSerializados,
    };
  }

  async listarOpcionesReprogramacionBorrador(conjuntoId: string, tareaId: number) {
    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      include: { operarios: { select: { id: true } } },
    });

    if (!tarea || !tarea.borrador || tarea.conjuntoId !== conjuntoId || tarea.tipo !== TipoTarea.PREVENTIVA) {
      throw new Error("No es una preventiva en borrador valida para reprogramar.");
    }

    const operariosIds = tarea.operarios.map((o) => o.id);
    // Ventana de búsqueda: la(s) plaza(s) de estos operarios si tienen
    // horario especial, o el horario general del conjunto (comportamiento
    // previo intacto cuando ninguno tiene plaza con horario propio).
    const horariosPorDia = await this.horariosPorDiaParaOperarios(conjuntoId, operariosIds);

    const inicioBase = new Date(tarea.fechaInicioOriginal ?? tarea.fechaInicio);
    const finBusqueda = new Date(inicioBase);
    finBusqueda.setDate(finBusqueda.getDate() + 7);
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioBase,
      fin: finBusqueda,
    });
    const opciones: Array<{ fecha: string; fechaInicio: string; fechaFin: string; duracionMinutos: number }> = [];

    let dia = new Date(inicioBase);
    dia.setDate(dia.getDate() + 1);

    for (let guard = 0; guard < 10 && opciones.length < 5; guard++) {
      const key = dayKey(dia);
      if (festivosSet.has(key)) {
        dia.setDate(dia.getDate() + 1);
        continue;
      }
      const horario = horariosPorDia.get(dateToDiaSemana(dia));
      if (!horario) {
        dia.setDate(dia.getDate() + 1);
        continue;
      }
      const disponibilidad = operariosIds.length
        ? await validarOperariosDisponiblesEnFecha({ prisma: this.prisma, fecha: dia, operariosIds })
        : { ok: true, noDisponibles: [] as string[] };
      if (!disponibilidad.ok) {
        dia.setDate(dia.getDate() + 1);
        continue;
      }

      const bloqueos = [
        ...buildBloqueosPorDescanso(horario),
        ...(await buildBloqueosPorPatronJornada({
          prisma: this.prisma,
          conjuntoId,
          fechaDia: dia,
          horarioDia: horario,
          operariosIds,
        })),
      ];

      let ocupadosGlobal: Intervalo[] = [];
      if (operariosIds.length) {
        const ini = new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), 0, 0, 0, 0);
        const fin = new Date(dia.getFullYear(), dia.getMonth(), dia.getDate(), 23, 59, 59, 999);
        const tareasDia = await this.prisma.tarea.findMany({
          where: {
            conjuntoId,
            id: { not: tareaId },
            fechaInicio: { lte: fin },
            fechaFin: { gte: ini },
            estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
            operarios: { some: { id: { in: operariosIds } } },
          },
          select: { fechaInicio: true, fechaFin: true },
        });
        const all: Intervalo[] = [];
        for (const t of tareasDia) {
          all.push({ i: toMinOfDay(t.fechaInicio), f: toMinOfDay(t.fechaFin) });
        }
        all.push(...bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })));
        ocupadosGlobal = mergeIntervalos(all);
      } else {
        ocupadosGlobal = mergeIntervalos(bloqueos.map((b) => ({ i: b.startMin, f: b.endMin })));
      }

      const bloques = buscarHuecoDiaConSplitEarliest({
        startMin: horario.startMin,
        endMin: horario.endMin,
        durMin: tarea.duracionMinutos ?? 60,
        ocupados: ocupadosGlobal,
        bloqueos,
        desiredStartMin: horario.startMin,
        maxBloques: 1,
      });

      if (bloques && bloques.length === 1) {
        const ini = toDateAtMin(dia, bloques[0].i);
        const fin = toDateAtMin(dia, bloques[0].f);
        opciones.push({
          fecha: key,
          fechaInicio: ini.toISOString(),
          fechaFin: fin.toISOString(),
          duracionMinutos: Math.max(1, Math.round((fin.getTime() - ini.getTime()) / 60000)),
        });
      }

      dia.setDate(dia.getDate() + 1);
    }

    return { tareaId, descripcion: tarea.descripcion, opciones };
  }

  async listarExcluidasBorrador(payload: unknown) {
    const dto = ListarExcluidasBorradorDTO.parse(payload);
    await this.limpiarExcluidasDeMesesAnteriores({
      conjuntoId: dto.conjuntoId,
      anio: dto.anio,
      mes: dto.mes,
    });
    const hayBorrador = await this.existeBorradorPreventivoMes({
      conjuntoId: dto.conjuntoId,
      anio: dto.anio,
      mes: dto.mes,
    });
    if (!hayBorrador) {
      return [];
    }
    const inicioDia = dto.fecha
      ? new Date(dto.fecha.getFullYear(), dto.fecha.getMonth(), dto.fecha.getDate(), 0, 0, 0, 0)
      : null;
    const finDia = dto.fecha
      ? new Date(dto.fecha.getFullYear(), dto.fecha.getMonth(), dto.fecha.getDate(), 23, 59, 59, 999)
      : null;

    return this.prisma.preventivaExcluidaBorrador.findMany({
      where: {
        conjuntoId: dto.conjuntoId,
        periodoAnio: dto.anio,
        periodoMes: dto.mes,
        estado: "PENDIENTE",
        ...(inicioDia && finDia
          ? { fechaObjetivo: { gte: inicioDia, lte: finDia } }
          : {}),
      },
      orderBy: [
        { prioridad: "asc" },
        { fechaObjetivo: "asc" },
        { id: "asc" },
      ],
    });
  }

  async descartarExcluidaBorrador(conjuntoId: string, excluidaId: number) {
    const excluida = await this.prisma.preventivaExcluidaBorrador.findFirst({
      where: {
        id: excluidaId,
        conjuntoId,
      },
      select: {
        id: true,
        conjuntoId: true,
        periodoAnio: true,
        periodoMes: true,
        descripcion: true,
        estado: true,
      },
    });

    if (!excluida) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }

    if (excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida ya no se puede descartar.");
    }

    await this.prisma.preventivaExcluidaBorrador.update({
      where: { id: excluidaId },
      data: {
        estado: "DESCARTADA",
        resueltaEn: new Date(),
      },
    });

    await this.registrarEventoBorrador({
      conjuntoId,
      periodoAnio: excluida.periodoAnio,
      periodoMes: excluida.periodoMes,
      tipo: "EXCLUIDA_DESCARTADA",
      accionAuditoria: AccionAuditoria.DESCARTAR_EXCLUIDA,
      excluidaId: excluida.id,
      detalle: `Se descartó manualmente la tarea excluida '${excluida.descripcion}'.`,
    });

    return { ok: true };
  }

  async sugerirHuecosExcluida(payload: unknown) {
    const dto = SugerirHuecosExcluidaDTO.parse(payload);
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
    });

    if (!excluida || excluida.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }

    return this.sugerirHuecosParaExcluidaCore({
      conjuntoId: dto.conjuntoId,
      excluida: {
        id: excluida.id,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        descripcion: excluida.descripcion,
        duracionMinutos: excluida.duracionMinutos,
        fechaObjetivo: excluida.fechaObjetivo,
        operariosIds: excluida.operariosIds,
      },
      fechaPreferida: dto.fechaPreferida,
      maxOpciones: dto.maxOpciones ?? 8,
    });
  }

  async agendarExcluidaBorrador(payload: unknown) {
    const dto = AgendarExcluidaDTO.parse(payload);
    const excluidaActual = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
      select: { id: true, conjuntoId: true, metadataJson: true },
    });
    if (!excluidaActual || excluidaActual.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }
    if ((this.leerDivisionManualExcluida(excluidaActual.metadataJson)?.bloques.length ?? 0) > 0) {
      throw new Error(
        "Esta tarea ya fue dividida manualmente. Agenda cada bloque por separado desde el desplegable.",
      );
    }

    let fechaInicio = dto.fechaInicio ?? null;
    let fechaFin = dto.fechaFin ?? null;
    let bloques = dto.bloques?.map((bloque) => ({
      fechaInicio: bloque.fechaInicio,
      fechaFin: bloque.fechaFin,
    })) ?? [];

    if (!fechaInicio && !fechaFin && bloques.length === 0) {
      const sugerencias = await this.sugerirHuecosExcluida({
        conjuntoId: dto.conjuntoId,
        excluidaId: dto.excluidaId,
        fechaPreferida: dto.fechaInicio ?? undefined,
        maxOpciones: 1,
      });
      const sugerida = sugerencias.opciones[0];
      if (!sugerida) {
        throw new Error("No se encontraron huecos disponibles para esta tarea excluida.");
      }
      bloques = ((sugerida.bloques as Array<{ fechaInicio: string; fechaFin: string }> | undefined) ?? [])
        .map((bloque) => ({
          fechaInicio: new Date(bloque.fechaInicio),
          fechaFin: new Date(bloque.fechaFin),
        }));
      if (!bloques.length) {
        fechaInicio = new Date(sugerida.fechaInicio);
        fechaFin = new Date(sugerida.fechaFin);
      }
    }

    const tareas = bloques.length
      ? await this.materializarExcluidaEnBloques({
          excluidaId: dto.excluidaId,
          conjuntoId: dto.conjuntoId,
          bloques,
        })
      : [
          await this.materializarExcluidaEnTarea({
            excluidaId: dto.excluidaId,
            conjuntoId: dto.conjuntoId,
            fechaInicio: fechaInicio!,
            fechaFin: fechaFin!,
          }),
        ];

    return { ok: true, tarea: tareas[0], tareas };
  }

  async reemplazarTareaBorradorConExcluida(payload: unknown) {
    const dto = ReemplazarConExcluidaDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      include: { operarios: { select: { id: true } } },
    });
    if (!tarea || !tarea.borrador || tarea.conjuntoId !== dto.conjuntoId) {
      throw new Error("La tarea del borrador no existe para este conjunto.");
    }

    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: dto.excluidaId },
    });
    if (!excluida || excluida.conjuntoId !== dto.conjuntoId || excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida no esta disponible para reemplazo.");
    }

    let fechaInicio = new Date(tarea.fechaInicio);
    let fechaFin = new Date(fechaInicio.getTime() + excluida.duracionMinutos * 60000);

    try {
      await this.validarSlotPreventivaBorrador({
        conjuntoId: dto.conjuntoId,
        fechaInicio,
        fechaFin,
        operariosIds: excluida.operariosIds,
        excluirTareaId: tarea.id,
        identidad: this.identidadDeExcluida(excluida),
      });
    } catch {
      const sugerencias = await this.sugerirHuecosParaExcluidaCore({
        conjuntoId: dto.conjuntoId,
        excluida: {
          id: excluida.id,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          descripcion: excluida.descripcion,
          duracionMinutos: excluida.duracionMinutos,
          fechaObjetivo: tarea.fechaInicio,
          operariosIds: excluida.operariosIds,
        },
        fechaPreferida: tarea.fechaInicio,
        maxOpciones: 1,
      });
      const sugerida = sugerencias.opciones[0];
      if (!sugerida) {
        throw new Error("No se encontro un hueco disponible para reemplazar esta tarea.");
      }
      fechaInicio = new Date(sugerida.fechaInicio);
      fechaFin = new Date(sugerida.fechaFin);
    }

    const excluidaGenerada = await this.crearExcluidaDesdeTarea({
      tareaId: tarea.id,
      motivoTipo: "MANUAL_REEMPLAZADA",
      motivoMensaje: `La tarea fue desplazada manualmente por '${excluida.descripcion}'.`,
      metadataJson: {
        reemplazadaPorExcluidaId: excluida.id,
        reemplazadaPorDescripcion: excluida.descripcion,
      },
    });

    await this.prisma.tarea.delete({ where: { id: tarea.id } });

    const nuevaTarea = await this.materializarExcluidaEnTarea({
      excluidaId: excluida.id,
      conjuntoId: dto.conjuntoId,
      fechaInicio,
      fechaFin,
    });

    await this.registrarEventoBorrador({
      conjuntoId: dto.conjuntoId,
      periodoAnio: excluida.periodoAnio,
      periodoMes: excluida.periodoMes,
      tipo: "REEMPLAZO_MANUAL",
      accionAuditoria: AccionAuditoria.REEMPLAZAR,
      detalle: `Se reemplazo manualmente la tarea '${tarea.descripcion}' por '${excluida.descripcion}'.`,
      tareaId: nuevaTarea.id,
      excluidaId: excluidaGenerada?.id ?? null,
      metadataJson: {
        tareaAnteriorId: tarea.id,
        tareaNuevaId: nuevaTarea.id,
        excluidaConsumidaId: excluida.id,
      },
    });

    return {
      ok: true,
      nuevaTarea,
      tareaEnviadaAExcluidasId: excluidaGenerada?.id ?? null,
    };
  }

  /* =========================
   * MAQUINARIA DISPONIBLE
   * ======================= */

  async listarMaquinariaDisponible(params: {
    conjuntoId: string;
    fechaInicioUso: Date;
    fechaFinUso: Date;
    excluirTareaId?: number;
    excluirGrupoPlanId?: string;
  }) {
    const {
      conjuntoId,
      fechaInicioUso,
      fechaFinUso,
      excluirTareaId,
      excluirGrupoPlanId,
    } = params;

    if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
      return { ok: false, reason: "FECHA_INICIO_INVALIDA" as const };
    }
    if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
      return { ok: false, reason: "FECHA_FIN_INVALIDA" as const };
    }
    if (+fechaFinUso < +fechaInicioUso) {
      return { ok: false, reason: "RANGO_INVERTIDO" as const };
    }

    const diasEntregaRecogida = DIAS_ENTREGA_RECOGIDA;

    const { iniReserva, finReserva, entregaDia, recogidaDia } =
      calcularRangoReserva({
        fechaInicioUso,
        fechaFinUso,
        diasEntregaRecogida,
      });

    const propias = await this.prisma.maquinaria.findMany({
      where: {
        propietarioTipo: "CONJUNTO",
        conjuntoPropietarioId: conjuntoId,
        estado: "OPERATIVA",
      },
      select: { id: true, nombre: true, tipo: true, marca: true, estado: true },
    });

    const empresa = await this.prisma.maquinaria.findMany({
      where: { propietarioTipo: "EMPRESA", estado: "OPERATIVA" },
      select: {
        id: true,
        nombre: true,
        tipo: true,
        marca: true,
        estado: true,
        empresaId: true,
      },
    });

    const idsInteres = Array.from(
      new Set([...propias.map((m) => m.id), ...empresa.map((m) => m.id)]),
    );

    if (!idsInteres.length) {
      return {
        ok: true,
        rango: { entregaDia, recogidaDia, iniReserva, finReserva },
        propiasDisponibles: [],
        empresaDisponibles: [],
        ocupadas: [],
      };
    }

    const overlaps = (aIni: Date, aFin: Date, bIni: Date, bFin: Date) =>
      aIni < bFin && bIni < aFin;

    const OPEN_END_FAR_FUTURE = new Date(2099, 11, 31, 23, 59, 59, 999);

    const ocupadasReservadas = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: { in: idsInteres },
        ...(excluirTareaId != null ? { tareaId: { not: excluirTareaId } } : {}),
        fechaInicio: { lt: finReserva },
        OR: [{ fechaFin: null }, { fechaFin: { gt: iniReserva } }],
      },
      select: {
        id: true,
        maquinariaId: true,
        tareaId: true,
        fechaInicio: true,
        fechaFin: true,
        tarea: {
          select: {
            id: true,
            conjuntoId: true,
            descripcion: true,
            estado: true,
            fechaInicio: true,
            fechaFin: true,
            borrador: true,
            grupoPlanId: true,
          },
        },
      },
    });

    const idsInteresSet = new Set(idsInteres);
    const bufferDiasBorrador = 4; // cubre corrimiento de entrega/recogida (L/X/S)
    const inicioBusquedaBorrador = new Date(iniReserva);
    inicioBusquedaBorrador.setDate(
      inicioBusquedaBorrador.getDate() - bufferDiasBorrador,
    );
    const finBusquedaBorrador = new Date(finReserva);
    finBusquedaBorrador.setDate(finBusquedaBorrador.getDate() + bufferDiasBorrador);

    const borradores = await this.prisma.tarea.findMany({
      where: {
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
        fechaInicio: { lt: finBusquedaBorrador },
        fechaFin: { gt: inicioBusquedaBorrador },
        ...(excluirTareaId != null ? { id: { not: excluirTareaId } } : {}),
      },
        select: {
          id: true,
          conjuntoId: true,
          descripcion: true,
          estado: true,
          fechaInicio: true,
          fechaFin: true,
          grupoPlanId: true,
          maquinariaPlanJson: true,
      },
      orderBy: [{ id: "asc" }],
    });

    type GrupoBorrador = {
      key: string;
      conjuntoId: string | null;
      descripcion: string | null;
      tareaIdRepresentante: number;
      maqIds: number[];
      usoIni: Date;
      usoFin: Date;
    };

    const gruposBorrador = new Map<string, GrupoBorrador>();

    for (const t of borradores) {
      const maqIds = Array.from(
        new Set(
          parseMaquinariaIdsComprometidos(t.maquinariaPlanJson).filter((id) => idsInteresSet.has(id)),
        ),
      );
      if (!maqIds.length) continue;

      const key = t.grupoPlanId ? `G:${t.grupoPlanId}` : `T:${t.id}`;
      const g = gruposBorrador.get(key);
      if (!g) {
        gruposBorrador.set(key, {
          key,
          conjuntoId: t.conjuntoId ?? null,
          descripcion: t.descripcion ?? null,
          tareaIdRepresentante: t.id,
          maqIds,
          usoIni: t.fechaInicio,
          usoFin: t.fechaFin,
        });
      } else {
        g.maqIds = Array.from(new Set(g.maqIds.concat(maqIds)));
        if (+t.fechaInicio < +g.usoIni) g.usoIni = t.fechaInicio;
        if (+t.fechaFin > +g.usoFin) g.usoFin = t.fechaFin;
        if (t.id < g.tareaIdRepresentante) {
          g.tareaIdRepresentante = t.id;
          g.descripcion = t.descripcion ?? g.descripcion;
          g.conjuntoId = t.conjuntoId ?? g.conjuntoId;
        }
      }
    }

    const ocupadasBorrador: Array<{
      maquinariaId: number;
      ini: Date;
      fin: Date;
      tareaId: number;
      conjuntoId: string | null;
      estado: string | null;
      descripcion: string;
      usoInicio: Date;
      usoFin: Date;
      fuente: "BORRADOR_PREVENTIVA";
    }> = [];

    for (const g of gruposBorrador.values()) {
      if (excluirGrupoPlanId && g.key === `G:${excluirGrupoPlanId}`) continue;

      const rangoBorrador = calcularRangoReserva({
        fechaInicioUso: g.usoIni,
        fechaFinUso: g.usoFin,
        diasEntregaRecogida,
      });

      if (
        !overlaps(
          iniReserva,
          finReserva,
          rangoBorrador.iniReserva,
          rangoBorrador.finReserva,
        )
      ) {
        continue;
      }

      const mismoConjunto = (g.conjuntoId ?? null) === conjuntoId;
      const solapeUsoReal = overlaps(
        fechaInicioUso,
        fechaFinUso,
        g.usoIni,
        g.usoFin,
      );
      if (mismoConjunto && !solapeUsoReal) {
        continue;
      }

      const desc = (g.descripcion ?? "Preventiva en borrador").trim();
      for (const maquinariaId of g.maqIds) {
        ocupadasBorrador.push({
          maquinariaId,
          ini: rangoBorrador.iniReserva,
          fin: rangoBorrador.finReserva,
          tareaId: g.tareaIdRepresentante,
          conjuntoId: g.conjuntoId ?? null,
          estado: EstadoTarea.ASIGNADA,
          descripcion: `[BORRADOR] ${desc}`,
          usoInicio: g.usoIni,
          usoFin: g.usoFin,
          fuente: "BORRADOR_PREVENTIVA",
        });
      }
    }

    const ocupadasDetalle = [
      ...ocupadasReservadas.map((o) => ({
        maquinariaId: o.maquinariaId,
        ini: o.fechaInicio,
        fin: o.fechaFin ?? OPEN_END_FAR_FUTURE,
        tareaId: o.tareaId,
        conjuntoId: o.tarea?.conjuntoId ?? null,
        estado: o.tarea?.estado ?? null,
        descripcion: o.tarea?.borrador
          ? `[BORRADOR] ${(o.tarea?.descripcion ?? "Tarea en borrador").trim()}`
          : o.tarea?.descripcion ?? null,
        usoInicio: o.tarea?.fechaInicio ?? o.fechaInicio,
        usoFin: o.tarea?.fechaFin ?? (o.fechaFin ?? OPEN_END_FAR_FUTURE),
        fuente: "RESERVA_PUBLICADA" as const,
      })),
      ...ocupadasBorrador,
    ];

    const nombrePorId = new Map(
      [...propias, ...empresa].map((maquina) => [maquina.id, maquina.nombre]),
    );

    const conjuntoIds = Array.from(
      new Set(
        [conjuntoId]
          .concat(
            ocupadasDetalle
          .map((item) => item.conjuntoId)
          .filter((item): item is string => !!item && item.trim().length > 0),
          ),
      ),
    );
    const conjuntos = conjuntoIds.length
      ? await this.prisma.conjunto.findMany({
          where: { nit: { in: conjuntoIds } },
          select: { nit: true, nombre: true },
        })
      : [];
    const conjuntoNombrePorId = new Map(
      conjuntos.map((conjunto) => [conjunto.nit, conjunto.nombre]),
    );

    const ocupadasDetalleConNombre = ocupadasDetalle.map((item) => ({
      ...item,
      maquinaNombre: nombrePorId.get(item.maquinariaId) ?? null,
      conjuntoNombre:
        item.conjuntoId == null ? null : (conjuntoNombrePorId.get(item.conjuntoId) ?? null),
    }));

    const descripcionSolicitada =
      excluirTareaId != null
        ? ((await this.prisma.tarea.findUnique({
            where: { id: excluirTareaId },
            select: { descripcion: true },
          }))?.descripcion ?? "Tarea reprogramada")
        : "Tarea solicitada";

    const conflictos = ocupadasDetalleConNombre.map((item) =>
      buildConflictoMaquinariaDetalle({
        maquinariaId: item.maquinariaId,
        maquinaNombre: item.maquinaNombre,
        tareaSolicitada: {
          tareaId: excluirTareaId ?? 0,
          descripcion: (descripcionSolicitada ?? "Tarea solicitada").trim() || "Tarea solicitada",
          conjuntoId,
          conjuntoNombre: conjuntoNombrePorId.get(conjuntoId) ?? null,
          estado: EstadoTarea.ASIGNADA,
          usoInicio: fechaInicioUso,
          usoFin: fechaFinUso,
          reservaInicio: iniReserva,
          reservaFin: finReserva,
          entregaDia,
          recogidaDia,
        },
        ocupadoPor: {
          usoId: 0,
          tareaId: item.tareaId,
          conjuntoId: item.conjuntoId,
          conjuntoNombre: item.conjuntoNombre,
          estado: item.estado,
          descripcion: item.descripcion,
          fuente: item.fuente,
          usoInicio: item.usoInicio,
          usoFin: item.usoFin,
          reservaInicio: item.ini,
          reservaFin: item.fin,
        },
        tipoSolape:
          item.fuente === "BORRADOR_PREVENTIVA"
            ? "BORRADOR_INTERNO"
            : (item.conjuntoId ?? null) === conjuntoId
              ? "USO_REAL"
              : "RESERVA_LOGISTICA",
        motivo:
          item.fuente === "BORRADOR_PREVENTIVA"
            ? "La maquina ya esta planificada en otro bloque preventivo que cruza este rango."
            : (item.conjuntoId ?? null) === conjuntoId
              ? "Se solapa el uso real de la maquina dentro del mismo conjunto."
              : "La ventana de reserva logistica de la maquina ya esta ocupada por otra tarea.",
      }),
    );

    const ocupadasSet = new Set(ocupadasDetalleConNombre.map((o) => o.maquinariaId));

    const propiasDisponibles = propias
      .filter((m) => !ocupadasSet.has(m.id))
      .map((m) => ({
        id: m.id,
        nombre: m.nombre,
        tipo: m.tipo,
        marca: m.marca,
        origen: "CONJUNTO" as const,
      }));

    const empresaDisponibles = empresa
      .filter((m) => !ocupadasSet.has(m.id))
      .map((m) => ({
        id: m.id,
        nombre: m.nombre,
        tipo: m.tipo,
        marca: m.marca,
        origen: "EMPRESA" as const,
        empresaId: m.empresaId,
      }));

    const propiasIds = new Set(propias.map((item) => item.id));

    const catalogo = [...propias, ...empresa]
      .map((m) => {
        const conflictos = ocupadasDetalleConNombre.filter((item) => item.maquinariaId === m.id);
        const origen = propiasIds.has(m.id) ? "CONJUNTO" : "EMPRESA";
        return {
          id: m.id,
          nombre: m.nombre,
          tipo: m.tipo,
          marca: m.marca,
          origen,
          disponible: conflictos.length === 0,
          motivo:
            conflictos.length === 0
              ? "Disponible para el rango solicitado."
              : conflictos.some((item) => item.fuente === "BORRADOR_PREVENTIVA")
                ? "Tiene preventivas definidas/borrador que se solapan con este rango."
                : "Tiene agenda publicada que se solapa con este rango.",
          conflictos: conflictos.map((item) => ({
            maquinariaId: item.maquinariaId,
            maquinaNombre: item.maquinaNombre,
            tareaId: item.tareaId,
            conjuntoId: item.conjuntoId,
            conjuntoNombre: item.conjuntoNombre,
            estado: item.estado,
            descripcion: item.descripcion,
            usoInicio: item.usoInicio,
            usoFin: item.usoFin,
            ini: item.ini,
            fin: item.fin,
            fuente: item.fuente,
          })),
        };
      })
      .sort((a, b) => {
        if (a.disponible !== b.disponible) return a.disponible ? -1 : 1;
        if (a.origen !== b.origen) return a.origen.localeCompare(b.origen);
        return a.nombre.localeCompare(b.nombre);
      });

      return {
        ok: true,
        rango: { entregaDia, recogidaDia, iniReserva, finReserva },
        propiasDisponibles,
        empresaDisponibles,
        ocupadas: ocupadasDetalleConNombre,
        catalogo,
        conflictos,
      };
  }

  async eliminarBloqueBorrador(conjuntoId: string, tareaId: number) {
    const tarea = await this.prisma.tarea.findFirst({
      where: {
        id: tareaId,
        conjuntoId,
        borrador: true,
        tipo: TipoTarea.PREVENTIVA,
      },
      select: {
        id: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        duracionMinutos: true,
        periodoAnio: true,
        periodoMes: true,
        ocurrenciaPlanId: true,
        grupoPlanId: true,
      },
    });
    if (!tarea) {
      throw new Error("Bloque no encontrado o no es borrador preventivo.");
    }

    await this.prisma.$transaction(async (tx) => {
      const serviceTx = new DefinicionTareaPreventivaService(
        tx as unknown as PrismaClient,
        this.actor,
      );
      const excluida = await serviceTx.crearExcluidaDesdeTarea({
        tareaId,
        motivoTipo: "MANUAL_ELIMINADA",
        motivoMensaje: "Este bloque fue retirado manualmente del borrador.",
        duracionMinutos: Math.max(1, tarea.duracionMinutos),
        fechaObjetivo: tarea.fechaInicio,
        metadataJson: {
          tareaIdsOriginales: [tareaId],
          bloquesEliminados: 1,
        },
      });
      if (!excluida) {
        throw new Error("No se pudo conservar la tarea en la lista de excluidas.");
      }

      // Las asignaciones reales de maquinaria referencian este bloque.
      await tx.usoMaquinaria.deleteMany({
        where: { tareaId: { in: [tareaId] } },
      });

      await serviceTx.auditarTarea({
        tareaId,
        conjuntoId,
        accion: AccionAuditoria.ELIMINAR,
        descripcion: `Se retiro manualmente el bloque '${tarea.descripcion}' del borrador y paso a excluidas.`,
        periodoAnio: tarea.periodoAnio,
        periodoMes: tarea.periodoMes,
        datosAntes: {
          fechaInicio: tarea.fechaInicio,
          fechaFin: tarea.fechaFin,
          tareaIds: [tareaId],
        },
      });

      await tx.tarea.deleteMany({ where: { id: { in: [tareaId] } } });
      if (tarea.grupoPlanId) {
        const restantes = await tx.tarea.findMany({
          where: { conjuntoId, borrador: true, grupoPlanId: tarea.grupoPlanId },
          select: { id: true },
          orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        });
        for (const [index, bloque] of restantes.entries()) {
          await tx.tarea.update({
            where: { id: bloque.id },
            data: restantes.length === 1
              ? { grupoPlanId: null, bloqueIndex: null, bloquesTotales: null }
              : { bloqueIndex: index + 1, bloquesTotales: restantes.length },
          });
        }
      }
      if (tarea.ocurrenciaPlanId) {
        await serviceTx.reconciliarOcurrenciaProgramada(tarea.ocurrenciaPlanId);
      }
    });
  }

  async listarBorrador(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador: true,
        periodoAnio: anio,
        periodoMes: mes,
        tipo: TipoTarea.PREVENTIVA,
      },
      include: tareaBorradorDetalleInclude,
      orderBy: [{ grupoPlanId: "asc" }, { bloqueIndex: "asc" }, { id: "asc" }],
    });
    // Color de la categoría para pintar las tarjetas del cronograma.
    return adjuntarCategoriaCronograma(this.prisma, tareas);
  }

  async informeMensualActividad(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
    borrador: boolean;
  }) {
    const { conjuntoId, anio, mes, borrador } = params;
    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId,
        borrador,
        tipo: TipoTarea.PREVENTIVA,
        periodoAnio: anio,
        periodoMes: mes,
      },
      select: {
        descripcion: true,
        duracionMinutos: true,
        fechaInicio: true,
      },
      orderBy: [{ descripcion: "asc" }, { fechaInicio: "asc" }],
    });

    const weekOfMonth = (fecha: Date) => {
      const firstDay = new Date(anio, mes - 1, 1);
      const offset = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1;
      return Math.min(5, Math.floor((fecha.getDate() + offset - 1) / 7) + 1);
    };

    const rows = new Map<string, {
      actividad: string;
      horasMes: number;
      semanas: Record<string, number>;
    }>();

    for (const tarea of tareas) {
      const actividad = tarea.descripcion.trim();
      const row = rows.get(actividad) ?? {
        actividad,
        horasMes: 0,
        semanas: { semana1: 0, semana2: 0, semana3: 0, semana4: 0, semana5: 0 },
      };
      const horas = Number((tarea.duracionMinutos / 60).toFixed(2));
      const semana = `semana${weekOfMonth(tarea.fechaInicio)}`;
      row.horasMes = Number((row.horasMes + horas).toFixed(2));
      row.semanas[semana] = Number(((row.semanas[semana] ?? 0) + horas).toFixed(2));
      rows.set(actividad, row);
    }

    return Array.from(rows.values()).sort((a, b) => a.actividad.localeCompare(b.actividad));
  }

  /* =========================
   * Reservas de maquinaria
   * ======================= */

  private async crearReservasPlanificadasParaTareas(params: {
    conjuntoId: string;
    tareas: Array<{
      id: number;
      grupoPlanId?: string | null;
      fechaInicio: Date;
      fechaFin: Date;
      maquinariaPlanJson: any;
      descripcion?: string | null;
    }>;
    diasEntregaRecogida: Set<number>;
    excluirTareaIds?: number[];
    festivosSet?: Set<string>;
  }) {
    const {
      conjuntoId,
      tareas,
      diasEntregaRecogida,
      excluirTareaIds = [],
      festivosSet,
    } = params;

    const sameDayKey = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    // 1) Agrupar por grupoPlanId
    type Grupo = {
      key: string; // "G:<grupoPlanId>" o "T:<tareaId>"
      tareaIds: number[];
      tareaIdRepresentante: number;
      descripcionRepresentante: string | null;
      maqIds: number[];
      usoIni: Date;
      usoFin: Date;
    };

    const grupos = new Map<string, Grupo>();

    for (const t of tareas) {
      const maqIds = parseMaquinariaIdsComprometidos(t.maquinariaPlanJson);
      if (!maqIds.length) continue;

      const key = t.grupoPlanId ? `G:${t.grupoPlanId}` : `T:${t.id}`;

      const g = grupos.get(key);
      if (!g) {
        grupos.set(key, {
          key,
          tareaIds: [t.id],
          tareaIdRepresentante: t.id,
          descripcionRepresentante: t.descripcion ?? null,
          maqIds: Array.from(new Set(maqIds)),
          usoIni: t.fechaInicio,
          usoFin: t.fechaFin,
        });
      } else {
        g.tareaIds.push(t.id);
        g.maqIds = Array.from(new Set(g.maqIds.concat(maqIds)));
        if (+t.fechaInicio < +g.usoIni) g.usoIni = t.fechaInicio;
        if (+t.fechaFin > +g.usoFin) g.usoFin = t.fechaFin;
        if (t.id < g.tareaIdRepresentante) {
          g.tareaIdRepresentante = t.id;
          g.descripcionRepresentante = t.descripcion ?? g.descripcionRepresentante;
        }
      }
    }

    // 2) Armar plan
    const plan = Array.from(grupos.values()).map((g) => {
      const { entregaDia, recogidaDia, iniReserva, finReserva } =
        calcularRangoReserva({
          fechaInicioUso: g.usoIni,
          fechaFinUso: g.usoFin,
          diasEntregaRecogida,
          festivosSet,
        });

      return {
        key: g.key,
        tareaIds: g.tareaIds,
        tareaIdRepresentante: g.tareaIdRepresentante,
        descripcion: g.descripcionRepresentante,
        maqIds: g.maqIds,
        usoIni: g.usoIni,
        usoFin: g.usoFin,
        entregaDia,
        recogidaDia,
        iniReserva,
        finReserva,
      };
    });

    if (!plan.length) return { ok: true, creadas: 0 };

    // 3) Query única
    const overlaps = (aIni: Date, aFin: Date, bIni: Date, bFin: Date) =>
      aIni < bFin && bIni < aFin;

    const conflictosInternos: Array<any> = [];
    for (let i = 0; i < plan.length; i++) {
      const a = plan[i];
      for (let j = i + 1; j < plan.length; j++) {
        const b = plan[j];
        if (a.key === b.key) continue;
        if (!overlaps(a.iniReserva, a.finReserva, b.iniReserva, b.finReserva))
          continue;
        const solapeUsoReal = overlaps(a.usoIni, a.usoFin, b.usoIni, b.usoFin);
        // Nueva regla:
        // Si la maquinaria ya esta en el conjunto y solo se solapan ventanas
        // de entrega/recogida (no el uso real), se permite reutilizarla.
        if (!solapeUsoReal) continue;

        const maqSetB = new Set<number>(b.maqIds);
        for (const maquinariaId of a.maqIds) {
          if (!maqSetB.has(maquinariaId)) continue;
          conflictosInternos.push(
            buildConflictoMaquinariaDetalle({
              maquinariaId,
              tareaSolicitada: {
                tareaId: a.tareaIdRepresentante,
                descripcion: (a.descripcion ?? "Preventiva en borrador").trim(),
                conjuntoId,
                conjuntoNombre: null,
                estado: EstadoTarea.ASIGNADA,
                usoInicio: a.usoIni,
                usoFin: a.usoFin,
                reservaInicio: a.iniReserva,
                reservaFin: a.finReserva,
                entregaDia: a.entregaDia,
                recogidaDia: a.recogidaDia,
              },
              ocupadoPor: {
                usoId: 0,
                tareaId: b.tareaIdRepresentante,
                conjuntoId,
                conjuntoNombre: null,
                estado: EstadoTarea.ASIGNADA,
                descripcion: `[BORRADOR] ${(b.descripcion ?? "Preventiva en borrador").trim()}`,
                fuente: "BORRADOR_PREVENTIVA",
                usoInicio: b.usoIni,
                usoFin: b.usoFin,
                reservaInicio: b.iniReserva,
                reservaFin: b.finReserva,
              },
              tipoSolape: "BORRADOR_INTERNO",
              motivo:
                "La maquina ya esta planificada en otro bloque preventivo del mismo borrador y ambos usos reales se cruzan.",
            }),
          );
        }
      }
    }

    const allMaqIds = Array.from(new Set(plan.flatMap((p) => p.maqIds)));
    const minIni = new Date(Math.min(...plan.map((p) => +p.iniReserva)));
    const maxFin = new Date(Math.max(...plan.map((p) => +p.finReserva)));
    const allPlanTareaIds = Array.from(
      new Set(plan.flatMap((p) => p.tareaIds)),
    );

    const conflictosDB = await this.prisma.usoMaquinaria.findMany({
      where: {
        maquinariaId: { in: allMaqIds },
        fechaInicio: { lt: maxFin },
        OR: [{ fechaFin: null }, { fechaFin: { gt: minIni } }],
        tareaId: { notIn: allPlanTareaIds.concat(excluirTareaIds) },
      },
      select: {
        id: true,
        maquinariaId: true,
        tareaId: true,
        fechaInicio: true,
        fechaFin: true,
        tarea: {
          select: {
            id: true,
            conjuntoId: true,
            descripcion: true,
            estado: true,
            fechaInicio: true,
            fechaFin: true,
            borrador: true,
          },
        },
      },
    });

    // 4) Validación exacta
    const OPEN_END_FAR_FUTURE = new Date(2099, 11, 31, 23, 59, 59, 999);

    const byMaq = new Map<number, typeof conflictosDB>();
    for (const u of conflictosDB) {
      const arr = byMaq.get(u.maquinariaId) ?? [];
      arr.push(u);
      byMaq.set(u.maquinariaId, arr);
    }

    const conflictos: Array<any> = [...conflictosInternos];

    for (const p of plan) {
      for (const maquinariaId of p.maqIds) {
        const ocup = byMaq.get(maquinariaId) ?? [];
        for (const u of ocup) {
          const uFin = u.fechaFin ?? OPEN_END_FAR_FUTURE;
          const solapeReserva = overlaps(
            p.iniReserva,
            p.finReserva,
            u.fechaInicio,
            uFin,
          );
          if (!solapeReserva) continue;

          const mismoConjunto = (u.tarea?.conjuntoId ?? null) === conjuntoId;
          if (mismoConjunto) {
            const usoOcupadoIni = u.tarea?.fechaInicio ?? u.fechaInicio;
            const usoOcupadoFin =
              u.tarea?.fechaFin ?? u.fechaFin ?? OPEN_END_FAR_FUTURE;
            const solapeUsoReal = overlaps(
              p.usoIni,
              p.usoFin,
              usoOcupadoIni,
              usoOcupadoFin,
            );
            // Regla nueva para mismo conjunto:
            // si no hay solape de uso real, se permite (la maquina permanece).
            if (!solapeUsoReal) continue;
          }

          conflictos.push(
            buildConflictoMaquinariaDetalle({
              maquinariaId,
              tareaSolicitada: {
                tareaId: p.tareaIdRepresentante,
                descripcion: (p.descripcion ?? "Preventiva en borrador").trim(),
                conjuntoId,
                conjuntoNombre: null,
                estado: EstadoTarea.ASIGNADA,
                usoInicio: p.usoIni,
                usoFin: p.usoFin,
                reservaInicio: p.iniReserva,
                reservaFin: p.finReserva,
                entregaDia: p.entregaDia,
                recogidaDia: p.recogidaDia,
              },
              ocupadoPor: {
                usoId: u.id,
                tareaId: u.tareaId,
                conjuntoId: u.tarea?.conjuntoId ?? null,
                conjuntoNombre: null,
                estado: u.tarea?.estado ?? null,
                descripcion: u.tarea?.borrador
                  ? `[BORRADOR] ${(u.tarea?.descripcion ?? "Tarea en borrador").trim()}`
                  : u.tarea?.descripcion ?? null,
                fuente: u.tarea?.borrador ? "BORRADOR_PUBLICADO" : "RESERVA_PUBLICADA",
                usoInicio: u.tarea?.fechaInicio ?? u.fechaInicio,
                usoFin: u.tarea?.fechaFin ?? (u.fechaFin ?? OPEN_END_FAR_FUTURE),
                reservaInicio: u.fechaInicio,
                reservaFin: u.fechaFin ?? OPEN_END_FAR_FUTURE,
              },
              tipoSolape: mismoConjunto ? "USO_REAL" : "RESERVA_LOGISTICA",
              motivo: mismoConjunto
                ? "Se solapa el uso real de la maquina con otra tarea del mismo conjunto."
                : "La ventana de reserva logistica de la maquina ya esta ocupada por otra tarea.",
            }),
          );
          break;
        }
      }
    }

    if (conflictos.length) {
      const maqIdsConflict = Array.from(
        new Set(conflictos.map((c) => c.maquinariaId)),
      );
      const maqs = await this.prisma.maquinaria.findMany({
        where: { id: { in: maqIdsConflict } },
        select: { id: true, nombre: true },
      });
      const nombrePorId = new Map(maqs.map((m) => [m.id, m.nombre]));

      const conjuntoIds = Array.from(
        new Set(
          conflictos
            .flatMap((c) => [c.tareaSolicitada.conjuntoId, c.ocupadoPor.conjuntoId])
            .filter((item): item is string => !!item),
        ),
      );
      const conjuntos = conjuntoIds.length
        ? await this.prisma.conjunto.findMany({
            where: { nit: { in: conjuntoIds } },
            select: { nit: true, nombre: true },
          })
        : [];
      const conjuntoNombrePorId = new Map(
        conjuntos.map((item) => [item.nit, item.nombre]),
      );

      const conflictosEnriquecidos: ConflictoMaquinaria[] = conflictos.map((item) => ({
        ...item,
        maquinaNombre: nombrePorId.get(item.maquinariaId) ?? item.maquinaNombre ?? null,
        tareaSolicitada: {
          ...item.tareaSolicitada,
          conjuntoNombre:
            item.tareaSolicitada.conjuntoId == null
              ? null
              : (conjuntoNombrePorId.get(item.tareaSolicitada.conjuntoId) ?? null),
        },
        ocupadoPor: {
          ...item.ocupadoPor,
          conjuntoNombre:
            item.ocupadoPor.conjuntoId == null
              ? null
              : (conjuntoNombrePorId.get(item.ocupadoPor.conjuntoId) ?? null),
        },
      }));

      const first = conflictosEnriquecidos[0];
      const maquinaNombre = nombrePorId.get(first.maquinariaId);

      throw buildMaquinariaNoDisponibleError({
        maquinariaId: first.maquinariaId,
        maquinaNombre,
        conflictos: conflictosEnriquecidos,
      });
    }

    // 5) Crear reservas (1 por grupo x máquina)
    const creadasIds: number[] = [];

    await this.prisma.$transaction(async (tx) => {
      for (const p of plan) {
        for (const maquinariaId of p.maqIds) {
          const existe = await tx.usoMaquinaria.findFirst({
            where: {
              tareaId: p.tareaIdRepresentante,
              maquinariaId,
              fechaInicio: p.iniReserva,
              fechaFin: p.finReserva,
            },
            select: { id: true },
          });

          if (!existe) {
            const created = await tx.usoMaquinaria.create({
              data: {
                tarea: { connect: { id: p.tareaIdRepresentante } },
                maquinaria: { connect: { id: maquinariaId } },
                fechaInicio: p.iniReserva,
                fechaFin: p.finReserva,
                observacion: `Reserva preventiva (${sameDayKey(p.entregaDia)}→${sameDayKey(p.recogidaDia)})`,
              },
              select: { id: true },
            });
            creadasIds.push(created.id);
          }

          await tx.maquinariaConjunto.updateMany({
            where: { conjuntoId, maquinariaId, estado: "ACTIVA" },
            data: { tareaId: p.tareaIdRepresentante },
          });
        }
      }
    });

    return { ok: true, creadas: creadasIds.length, ids: creadasIds };
  }

  /* =========================
   * Reserva: utilidades
   * ======================= */

}

/* =========================================================
 * Helpers (FUERA de la clase)
 * ======================================================= */

type Intervalo = { i: number; f: number };

function enumerateDays(start: Date, end: Date): Date[] {
  const out: Date[] = [];
  const cur = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const last = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  while (cur <= last) {
    out.push(new Date(cur));
    cur.setDate(cur.getDate() + 1);
  }
  return out;
}

function construirVentanasTrabajoDia(horario: HorarioDia): Intervalo[] {
  const bloqueos = buildBloqueosPorDescanso(horario).sort(
    (a, b) => a.startMin - b.startMin,
  );
  const ventanas: Intervalo[] = [];
  let cursor = horario.startMin;

  for (const bloqueo of bloqueos) {
    if (bloqueo.startMin > cursor) {
      ventanas.push({ i: cursor, f: bloqueo.startMin });
    }
    cursor = Math.max(cursor, bloqueo.endMin);
  }

  if (cursor < horario.endMin) {
    ventanas.push({ i: cursor, f: horario.endMin });
  }

  return ventanas.filter((ventana) => ventana.f > ventana.i);
}

const MENSAJE_REORDEN_NO_CABE =
  "No se pudo reordenar porque el nuevo orden no cabe dentro de la jornada laboral del día.";

/** Un tramo menor a esto antes del almuerzo se salta en vez de partir la tarea. */
const MIN_TRAMO_ANTES_ALMUERZO_MIN = 15;

function distribuirDuracionReordenamiento(params: {
  fecha: Date;
  ventanas: Intervalo[];
  inicioCursor: Date;
  duracionMinutos: number;
  horario: HorarioDia;
}): Array<{ fechaInicio: Date; fechaFin: Date }> {
  // Primero se evita dejar un tramo diminuto pegado al almuerzo (la tarea
  // se ve cortada); si así no cabe, se permite como antes.
  try {
    return distribuirDuracionReordenamientoBase(
      params,
      MIN_TRAMO_ANTES_ALMUERZO_MIN,
    );
  } catch (error) {
    if (!(error instanceof Error) || error.message !== MENSAJE_REORDEN_NO_CABE) {
      throw error;
    }
    return distribuirDuracionReordenamientoBase(params, 0);
  }
}

function distribuirDuracionReordenamientoBase(
  params: {
    fecha: Date;
    ventanas: Intervalo[];
    inicioCursor: Date;
    duracionMinutos: number;
    horario: HorarioDia;
  },
  minTramoAntesAlmuerzo: number,
): Array<{ fechaInicio: Date; fechaFin: Date }> {
  const { fecha, ventanas, inicioCursor, duracionMinutos, horario } = params;
  const duracion = Math.max(1, Math.round(duracionMinutos));
  const cursorMin = toMinOfDay(inicioCursor);
  const ventanasOrdenadas = mergeIntervalos(ventanas).sort((a, b) => (a.i - b.i) || (a.f - b.f));

  for (let index = 0; index < ventanasOrdenadas.length; index += 1) {
    const ventana = ventanasOrdenadas[index];
    const inicioSegmento = Math.max(cursorMin, ventana.i);
    if (inicioSegmento >= ventana.f) continue;

    const disponibleActual = ventana.f - inicioSegmento;
    if (disponibleActual >= duracion) {
      return [
        {
          fechaInicio: toDateAtMin(fecha, inicioSegmento),
          fechaFin: toDateAtMin(fecha, inicioSegmento + duracion),
        },
      ];
    }

    const siguienteVentana = ventanasOrdenadas[index + 1];
    const puedeCruzarAlmuerzo =
      horario.descansoStartMin != null &&
      horario.descansoEndMin != null &&
      ventana.f === horario.descansoStartMin &&
      siguienteVentana?.i === horario.descansoEndMin;

    if (!puedeCruzarAlmuerzo) continue;
    if (disponibleActual < minTramoAntesAlmuerzo) continue;

    const restante = duracion - disponibleActual;
    const disponibleSiguiente = (siguienteVentana?.f ?? 0) - (siguienteVentana?.i ?? 0);
    if (restante <= 0 || !siguienteVentana || disponibleSiguiente < restante) continue;

    return [
      {
        fechaInicio: toDateAtMin(fecha, inicioSegmento),
        fechaFin: toDateAtMin(fecha, ventana.f),
      },
      {
        fechaInicio: toDateAtMin(fecha, siguienteVentana.i),
        fechaFin: toDateAtMin(fecha, siguienteVentana.i + restante),
      },
    ];
  }

  throw new Error(MENSAJE_REORDEN_NO_CABE);
}

function intentarDistribuirDuracionReordenamiento(params: {
  fecha: Date;
  ventanas: Intervalo[];
  inicioCursor: Date;
  duracionMinutos: number;
  horario: HorarioDia;
}): Array<{ fechaInicio: Date; fechaFin: Date }> | null {
  if (!params.ventanas.length) return null;

  try {
    return distribuirDuracionReordenamiento(params);
  } catch (error) {
    if (error instanceof Error && error.message === MENSAJE_REORDEN_NO_CABE) {
      return null;
    }
    throw error;
  }
}

function calcularDuracionLaboralReordenamiento(params: {
  tarea: { fechaInicio: Date; fechaFin: Date; duracionMinutos?: number | null };
  horario: HorarioDia;
}): number {
  const { tarea, horario } = params;
  const inicioMin = toMinOfDay(tarea.fechaInicio);
  const finMin = toMinOfDay(tarea.fechaFin);
  const duracionRango = Math.max(1, finMin - inicioMin);

  const minutosDescanso = buildBloqueosPorDescanso(horario).reduce((acc, bloqueo) => {
    const solapeInicio = Math.max(inicioMin, bloqueo.startMin);
    const solapeFin = Math.min(finMin, bloqueo.endMin);
    return acc + Math.max(0, solapeFin - solapeInicio);
  }, 0);

  const duracionLaboral = duracionRango - minutosDescanso;
  if (duracionLaboral > 0) {
    return duracionLaboral;
  }

  return Math.max(1, tarea.duracionMinutos ?? 1);
}

function construirVentanasOcupadasReordenamiento(params: {
  tareas: Array<{ fechaInicio: Date; fechaFin: Date }>;
  ventanasTrabajo: Intervalo[];
}): Intervalo[] {
  const { tareas, ventanasTrabajo } = params;
  const ocupadas: Intervalo[] = [];

  for (const tarea of tareas) {
    const inicioMin = toMinOfDay(tarea.fechaInicio);
    const finMin = toMinOfDay(tarea.fechaFin);
    if (finMin <= inicioMin) continue;

    for (const ventana of ventanasTrabajo) {
      const i = Math.max(inicioMin, ventana.i);
      const f = Math.min(finMin, ventana.f);
      if (f > i) {
        ocupadas.push({ i, f });
      }
    }
  }

  return mergeIntervalos(ocupadas).sort((a, b) => (a.i - b.i) || (a.f - b.f));
}

function buildTareaBorradorCreateData(
  original: any,
  fechaInicio: Date,
  fechaFin: Date,
): Prisma.TareaCreateInput {
  const duracionMinutos = Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000));

  return {
    descripcion: original.descripcion,
    fechaInicio,
    fechaFin,
    fechaIniciarTarea: original.fechaIniciarTarea,
    fechaFinalizarTarea: original.fechaFinalizarTarea,
    duracionMinutos,
    prioridad: original.prioridad ?? 2,
    estado: original.estado,
    evidencias: original.evidencias ?? [],
    insumosUsados:
      original.insumosUsados == null
        ? undefined
        : (original.insumosUsados as Prisma.InputJsonValue),
    observaciones: original.observaciones,
    observacionesRechazo: original.observacionesRechazo,
    fechaVerificacion: original.fechaVerificacion,
    finalizadaPorId: original.finalizadaPorId,
    finalizadaPorRol: original.finalizadaPorRol,
    supervisor: original.supervisorId ? { connect: { id: original.supervisorId } } : undefined,
    ubicacion: { connect: { id: original.ubicacionId } },
    elemento: { connect: { id: original.elementoId } },
    conjunto: original.conjuntoId ? { connect: { nit: original.conjuntoId } } : undefined,
    empresaAprobada: original.empresaAprobadaId
      ? { connect: { id: original.empresaAprobadaId } }
      : undefined,
    empresaRechazada: original.empresaRechazadaId
      ? { connect: { id: original.empresaRechazadaId } }
      : undefined,
    tipo: original.tipo,
    frecuencia: original.frecuencia,
    definicionId: original.definicionId ?? null,
    ocurrenciaPlanId: original.ocurrenciaPlanId ?? null,
    diaSemanaProgramado: original.diaSemanaProgramado ?? null,
    borrador: true,
    periodoAnio: fechaInicio.getFullYear(),
    periodoMes: fechaInicio.getMonth() + 1,
    grupoPlanId: original.grupoPlanId,
    bloqueIndex: original.bloqueIndex,
    bloquesTotales: original.bloquesTotales,
    tiempoEstimadoMinutos: original.tiempoEstimadoMinutos,
    insumoPrincipal: original.insumoPrincipalId
      ? { connect: { id: original.insumoPrincipalId } }
      : undefined,
    consumoPrincipalPorUnidad: original.consumoPrincipalPorUnidad,
    consumoTotalEstimado: original.consumoTotalEstimado,
    insumosPlanJson:
      original.insumosPlanJson == null
        ? undefined
        : (original.insumosPlanJson as Prisma.InputJsonValue),
    maquinariaPlanJson:
      original.maquinariaPlanJson == null
        ? undefined
        : (original.maquinariaPlanJson as Prisma.InputJsonValue),
    herramientasPlanJson:
      original.herramientasPlanJson == null
        ? undefined
        : (original.herramientasPlanJson as Prisma.InputJsonValue),
    reprogramada: original.reprogramada ?? false,
    reprogramadaEn: original.reprogramadaEn,
    reprogramadaMotivo: original.reprogramadaMotivo,
    reprogramadaPorTareaId: original.reprogramadaPorTareaId,
    fechaInicioOriginal: original.fechaInicioOriginal,
    fechaFinOriginal: original.fechaFinOriginal,
    operarios: original.operarios?.length
      ? {
          connect: original.operarios.map((operario: { id: string }) => ({
            id: operario.id,
          })),
        }
      : undefined,
    // Conserva el vínculo a la(s) plaza(s) de origen al recrear el bloque
    // (reordenamiento del día): sin esto se perdía el distintivo visual de
    // horario especial.
    necesidades: original.necesidades?.length
      ? {
          connect: original.necesidades.map((necesidad: { id: number }) => ({
            id: necesidad.id,
          })),
        }
      : undefined,
  };
}

export function buildBloqueosPorDescanso(horario: HorarioDia): Bloqueo[] {
  const ds = horario.descansoStartMin;
  const df = horario.descansoEndMin;

  if (ds == null || df == null) return [];
  if (!(horario.startMin < ds && ds < df && df < horario.endMin)) return [];

  return [{ startMin: ds, endMin: df, motivo: "DESCANSO" }];
}

function dateToDiaSemana(d: Date): DiaSemana {
  switch (d.getDay()) {
    case 0:
      return DiaSemana.DOMINGO;
    case 1:
      return DiaSemana.LUNES;
    case 2:
      return DiaSemana.MARTES;
    case 3:
      return DiaSemana.MIERCOLES;
    case 4:
      return DiaSemana.JUEVES;
    case 5:
      return DiaSemana.VIERNES;
    case 6:
      return DiaSemana.SABADO;
    default:
      return DiaSemana.LUNES;
  }
}

function inicioSemana(fecha: Date): Date {
  const d = new Date(fecha);
  const day = d.getDay();
  const diff = d.getDate() - day + (day === 0 ? -6 : 1); // lunes
  return new Date(d.getFullYear(), d.getMonth(), diff, 0, 0, 0, 0);
}

async function minutosAsignadosEnSemana(
  prisma: PrismaClient | Prisma.TransactionClient,
  conjuntoId: string,
  operarioId: string,
  fecha: Date,
  incluirPublicadas: boolean,
): Promise<number> {
  const ini = inicioSemana(fecha);
  const fin = new Date(ini);
  fin.setDate(ini.getDate() + 6);

  const where: any = {
    conjuntoId,
    operarios: { some: { id: operarioId.toString() } },
    fechaInicio: { lte: fin },
    fechaFin: { gte: ini },
    estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
  };

  if (!incluirPublicadas) where.borrador = true;

  const tareas = await prisma.tarea.findMany({
    where,
    select: { duracionMinutos: true },
  });

  return tareas.reduce((acc, t) => acc + (t.duracionMinutos ?? 0), 0);
}

async function existeSolapeParaOperario(
  prisma: PrismaClient | Prisma.TransactionClient,
  params: {
    conjuntoId: string;
    operarioId: string | number;
    fechaInicio: Date;
    fechaFin: Date;
    soloBorrador?: boolean;
    excluirTareaId?: number;
    excluirEstados?: string[];
  },
): Promise<boolean> {
  const {
    conjuntoId,
    operarioId,
    fechaInicio,
    fechaFin,
    soloBorrador = true,
    excluirTareaId,
    excluirEstados = [],
  } = params;

  const where: any = {
    conjuntoId,
    tipo: { in: [TipoTarea.PREVENTIVA, TipoTarea.CORRECTIVA] as any },
    operarios: { some: { id: operarioId.toString() } },
    fechaInicio: { lt: fechaFin },
    fechaFin: { gt: fechaInicio },
  };

  if (soloBorrador) where.borrador = true;
  if (excluirEstados.length) where.estado = { notIn: excluirEstados as any };
  if (excluirTareaId != null) where.id = { not: excluirTareaId };

  const overlap = await prisma.tarea.findFirst({ where, select: { id: true } });
  return Boolean(overlap);
}

async function getOperarioNombre(
  prisma: PrismaClient | Prisma.TransactionClient,
  operarioId: string | number,
): Promise<string> {
  const idStr = operarioId.toString();
  const op = await prisma.operario.findUnique({
    where: { id: idStr },
    select: { usuario: { select: { nombre: true } } },
  });

  return op?.usuario?.nombre ?? `Operario ${idStr}`;
}

async function construirMensajeSinDisponibilidadOperarios(
  prisma: PrismaClient | Prisma.TransactionClient,
  operariosIds: Array<string | number>,
): Promise<string> {
  const nombres = await Promise.all(
    operariosIds.map((operarioId) => getOperarioNombre(prisma, operarioId)),
  );
  const nombresUnicos = Array.from(
    new Set(nombres.map((nombre) => nombre.trim()).filter(Boolean)),
  );

  if (nombresUnicos.length <= 1) {
    return `El operario ${nombresUnicos[0] ?? "seleccionado"} no tiene disponibilidad para ese día.`;
  }

  return `Los operarios ${nombresUnicos.join(", ")} no tienen disponibilidad para ese día.`;
}

function formatHoraLocal(fecha: Date): string {
  return `${String(fecha.getHours()).padStart(2, "0")}:${String(fecha.getMinutes()).padStart(2, "0")}`;
}

function formatFechaLocal(fecha: Date): string {
  return `${String(fecha.getDate()).padStart(2, "0")}/${String(fecha.getMonth() + 1).padStart(2, "0")}/${fecha.getFullYear()}`;
}

function sameDayKeyLocal(fecha: Date): string {
  return `${fecha.getFullYear()}-${String(fecha.getMonth() + 1).padStart(2, "0")}-${String(fecha.getDate()).padStart(2, "0")}`;
}

function buildSugerenciaConflictoMaquinaria(params: {
  tipoSolape: ConflictoMaquinaria["tipoSolape"];
  tareaSolicitada: {
    usoInicio: Date;
    usoFin: Date;
  };
  ocupadoPor: {
    usoFin: Date;
    reservaFin: Date;
  };
}) {
  const { tipoSolape, tareaSolicitada, ocupadoPor } = params;
  const duracionMs = Math.max(
    60000,
    tareaSolicitada.usoFin.getTime() - tareaSolicitada.usoInicio.getTime(),
  );
  const baseFin =
    tipoSolape === "RESERVA_LOGISTICA"
      ? ocupadoPor.reservaFin
      : ocupadoPor.usoFin;

  if (baseFin.getFullYear() >= 2099) {
    return {
      libreDesde: null,
      inicioUsoSugerido: null,
      finUsoSugerido: null,
      nota:
        "La reserva ocupante no tiene fecha de cierre registrada. Revisa y cierra esa reserva antes de reprogramar.",
    };
  }

  const inicioUsoSugerido = new Date(baseFin.getTime() + 60000);
  const finUsoSugerido = new Date(inicioUsoSugerido.getTime() + duracionMs);

  return {
    libreDesde: baseFin.toISOString(),
    inicioUsoSugerido: inicioUsoSugerido.toISOString(),
    finUsoSugerido: finUsoSugerido.toISOString(),
    nota:
      tipoSolape === "RESERVA_LOGISTICA"
        ? "Este es el primer reintento despues de que termina la reserva ocupante. Debe validarse nuevamente contra toda la agenda."
        : "Este es el primer reintento despues de que termina el uso real ocupante. Debe validarse nuevamente contra toda la agenda.",
  };
}

function buildConflictoMaquinariaDetalle(params: {
  maquinariaId: number;
  maquinaNombre?: string | null;
  tareaSolicitada: {
    tareaId: number;
    descripcion: string;
    conjuntoId: string | null;
    conjuntoNombre?: string | null;
    estado?: string | null;
    usoInicio: Date;
    usoFin: Date;
    reservaInicio: Date;
    reservaFin: Date;
    entregaDia: Date;
    recogidaDia: Date;
  };
  ocupadoPor: {
    usoId: number;
    tareaId: number;
    conjuntoId: string | null;
    conjuntoNombre?: string | null;
    estado?: string | null;
    descripcion: string | null;
    fuente: string;
    usoInicio: Date;
    usoFin: Date;
    reservaInicio: Date;
    reservaFin: Date;
  };
  tipoSolape: ConflictoMaquinaria["tipoSolape"];
  motivo: string;
}): ConflictoMaquinaria {
  const { maquinariaId, maquinaNombre, tareaSolicitada, ocupadoPor, tipoSolape, motivo } =
    params;

  return {
    maquinariaId,
    maquinaNombre: maquinaNombre ?? null,
    tareaSolicitada: {
      tareaId: tareaSolicitada.tareaId,
      descripcion: tareaSolicitada.descripcion,
      conjuntoId: tareaSolicitada.conjuntoId,
      conjuntoNombre: tareaSolicitada.conjuntoNombre ?? null,
      estado: tareaSolicitada.estado ?? null,
      usoInicio: tareaSolicitada.usoInicio.toISOString(),
      usoFin: tareaSolicitada.usoFin.toISOString(),
      reservaInicio: tareaSolicitada.reservaInicio.toISOString(),
      reservaFin: tareaSolicitada.reservaFin.toISOString(),
      entrega: sameDayKeyLocal(tareaSolicitada.entregaDia),
      recogida: sameDayKeyLocal(tareaSolicitada.recogidaDia),
    },
    ocupadoPor: {
      usoId: ocupadoPor.usoId,
      tareaId: ocupadoPor.tareaId,
      conjuntoId: ocupadoPor.conjuntoId,
      conjuntoNombre: ocupadoPor.conjuntoNombre ?? null,
      estado: ocupadoPor.estado ?? null,
      descripcion: ocupadoPor.descripcion,
      fuente: ocupadoPor.fuente,
      usoInicio: ocupadoPor.usoInicio.toISOString(),
      usoFin: ocupadoPor.usoFin.toISOString(),
      reservaInicio: ocupadoPor.reservaInicio.toISOString(),
      reservaFin: ocupadoPor.reservaFin.toISOString(),
    },
    tipoSolape,
    motivo,
    sugerencia: buildSugerenciaConflictoMaquinaria({
      tipoSolape,
      tareaSolicitada: {
        usoInicio: tareaSolicitada.usoInicio,
        usoFin: tareaSolicitada.usoFin,
      },
      ocupadoPor: {
        usoFin: ocupadoPor.usoFin,
        reservaFin: ocupadoPor.reservaFin,
      },
    }),
  };
}

/**
 * Estimación liviana de la duración de una ocurrencia, usada solo para
 * ordenar la cola de trabajo (definiciones más largas primero dentro de
 * cada ronda). El cálculo real y determinante de cada bloque se sigue
 * haciendo dentro del ciclo de programación con `calcularMinutosEstimados`.
 */
export function estimarDuracionDefinicionMin(
  def: any,
  tamanoBloqueMinutos: number,
): number {
  const minutosEstimados =
    calcularMinutosEstimados({
      cantidad: def.areaNumerica != null ? Number(def.areaNumerica) : undefined,
      rendimiento:
        def.rendimientoBase != null ? Number(def.rendimientoBase) : undefined,
      duracionMinutosFija: def.duracionMinutosFija ?? undefined,
      rendimientoTiempoBase: def.rendimientoTiempoBase ?? "POR_HORA",
    }) ??
    (def.duracionMinutosFija != null ? Number(def.duracionMinutosFija) : null) ??
    (def.duracionHorasFija != null
      ? Math.max(1, Math.round(Number(def.duracionHorasFija) * 60))
      : null) ??
    null;
  return minutosEstimados ?? tamanoBloqueMinutos;
}

export function pickDaysByFrecuencia(days: Date[], def: any): Date[] {
  switch (def.frecuencia) {
    case Frecuencia.DIARIA:
      return days;

    case Frecuencia.SEMANAL: {
      const dia = def.diaSemanaProgramado ?? DiaSemana.LUNES;
      const target = diaSemanaToJsDay(dia);
      return days.filter((d) => d.getDay() === target);
    }

    case Frecuencia.QUINCENAL: {
      // Igual que SEMANAL pero cada dos semanas: se conservan la 1a y la 3a
      // ocurrencia del dia elegido dentro del mes (14 dias exactos de separacion).
      if (def.diaSemanaProgramado) {
        const target = diaSemanaToJsDay(def.diaSemanaProgramado);
        const ocurrencias = days.filter((d) => d.getDay() === target);
        return ocurrencias.filter((_, index) => index % 2 === 0 && index < 4);
      }
      // Definiciones antiguas sin dia de semana: se mantiene el calculo por fecha ancla.
      const ancla = construirFechaAnclaFrecuencia(def);
      return days.filter((d) => diferenciaDiasCalendario(ancla, d) % 14 === 0);
    }

    case Frecuencia.MENSUAL: {
      return filtrarPorIntervaloMensual(days, def, 1);
    }

    case Frecuencia.BIMESTRAL: {
      return filtrarPorFechasExplicitas(days, def);
    }

    case Frecuencia.TRIMESTRAL: {
      return filtrarPorFechasExplicitas(days, def);
    }

    case Frecuencia.SEMESTRAL: {
      return filtrarPorFechasExplicitas(days, def);
    }

    case Frecuencia.ANUAL: {
      return filtrarPorFechasExplicitas(days, def);
    }

    default:
      return days;
  }
}

function filtrarPorIntervaloMensual(days: Date[], def: any, intervaloMeses: number): Date[] {
  if (!days.length) return [];

  const ancla = construirFechaAnclaFrecuencia(def);
  const diaObjetivo = Math.max(1, Math.min(31, Number(def.diaMesProgramado ?? ancla.getDate() ?? 1)));

  return days.filter((d) => {
    if (mesesEntre(ancla, d) % intervaloMeses !== 0) return false;
    return d.getDate() === ajustarDiaMes(d.getFullYear(), d.getMonth(), diaObjetivo);
  });
}

function filtrarPorFechasExplicitas(days: Date[], def: any): Date[] {
  const fechas = normalizarFechasProgramadas(def.fechasProgramadasJson);
  if (!fechas.length) return [];

  const claves = new Set(
    fechas.map((fecha) => `${fecha.getMonth() + 1}-${fecha.getDate()}`),
  );

  return days.filter((d) => claves.has(`${d.getMonth() + 1}-${d.getDate()}`));
}

function construirFechaAnclaFrecuencia(def: any): Date {
  const base = def.creadoEn instanceof Date ? def.creadoEn : new Date(def.creadoEn ?? Date.now());
  const diaObjetivo = Math.max(1, Math.min(31, Number(def.diaMesProgramado ?? base.getDate() ?? 1)));
  return new Date(
    base.getFullYear(),
    base.getMonth(),
    ajustarDiaMes(base.getFullYear(), base.getMonth(), diaObjetivo),
  );
}

function normalizarFechasProgramadas(value: unknown): Date[] {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => {
      const raw = typeof item === "string" ? item : item?.toString();
      if (!raw) return null;
      const parsed = new Date(`${raw}T00:00:00`);
      return Number.isNaN(parsed.getTime()) ? null : parsed;
    })
    .filter((item): item is Date => item instanceof Date);
}

function ajustarDiaMes(anio: number, mesIndex: number, dia: number): number {
  return Math.min(dia, new Date(anio, mesIndex + 1, 0).getDate());
}

function mesesEntre(a: Date, b: Date): number {
  return (b.getFullYear() - a.getFullYear()) * 12 + (b.getMonth() - a.getMonth());
}

function diferenciaDiasCalendario(a: Date, b: Date): number {
  const utcA = Date.UTC(a.getFullYear(), a.getMonth(), a.getDate());
  const utcB = Date.UTC(b.getFullYear(), b.getMonth(), b.getDate());
  return Math.round((utcB - utcA) / 86400000);
}

function diaSemanaToJsDay(d: DiaSemana): number {
  switch (d) {
    case DiaSemana.DOMINGO:
      return 0;
    case DiaSemana.LUNES:
      return 1;
    case DiaSemana.MARTES:
      return 2;
    case DiaSemana.MIERCOLES:
      return 3;
    case DiaSemana.JUEVES:
      return 4;
    case DiaSemana.VIERNES:
      return 5;
    case DiaSemana.SABADO:
      return 6;
  }
}

/**
 * ✅ Límite semanal (minutos) por conjunto:
 * - si Conjunto.limiteHorasSemanaOverride existe -> usa ese
 * - si no, usa Empresa.limiteHorasSemana de la empresa del conjunto
 * - fallback: 42h
 */
async function getLimiteMinSemanaPorConjunto(
  prisma: PrismaClient | Prisma.TransactionClient,
  conjuntoId: string,
): Promise<number> {
  const conjunto = await prisma.conjunto.findUnique({
    where: { nit: conjuntoId },
    select: {
      limiteHorasSemanaOverride: true,
      empresa: { select: { limiteHorasSemana: true } },
    },
  });

  const override = conjunto?.limiteHorasSemanaOverride;
  if (override != null) return override * 60;

  return (conjunto?.empresa?.limiteHorasSemana ?? 42) * 60;
}

/* =========================================================
 * Patrones de jornada -> bloqueos
 * ======================================================= */

function clampInterval(i: number, f: number, start: number, end: number) {
  const ii = Math.max(i, start);
  const ff = Math.min(f, end);
  return ff > ii ? { i: ii, f: ff } : null;
}

function bloqueosFromAllowed(params: {
  horario: HorarioDia;
  allowed: Array<{ i: number; f: number }>;
  motivo: string;
}): Bloqueo[] {
  const { horario, allowed, motivo } = params;

  if (!allowed.length) {
    return [{ startMin: horario.startMin, endMin: horario.endMin, motivo }];
  }

  const out: Bloqueo[] = [];
  const ordenados = [...allowed]
    .map((intervalo) => ({
      i: Math.max(horario.startMin, intervalo.i),
      f: Math.min(horario.endMin, intervalo.f),
    }))
    .filter((intervalo) => intervalo.f > intervalo.i)
    .sort((a, b) => a.i - b.i);
  let cursor = horario.startMin;
  for (const intervalo of ordenados) {
    if (intervalo.i > cursor) {
      out.push({ startMin: cursor, endMin: intervalo.i, motivo });
    }
    cursor = Math.max(cursor, intervalo.f);
  }
  if (cursor < horario.endMin) {
    out.push({ startMin: cursor, endMin: horario.endMin, motivo });
  }

  return out;
}

/**
 * Bloqueos por patrón (si uno NO puede, se bloquea).
 */
export async function buildBloqueosPorPatronJornada(params: {
  prisma: PrismaClient;
  conjuntoId: string;
  fechaDia: Date;
  horarioDia: HorarioDia;
  operariosIds: string[];
}): Promise<Bloqueo[]> {
  const { prisma, conjuntoId, fechaDia, horarioDia, operariosIds } = params;
  if (!operariosIds.length) return [];

  const disponibilidad = await obtenerIntervalosEfectivosProgramacion({
    prisma,
    conjuntoId,
    fecha: fechaDia,
    operariosIds,
  });
  return bloqueosFromAllowed({
    horario: horarioDia,
    allowed: disponibilidad.intervalosEfectivos,
    motivo: "JORNADA_OPERARIOS",
  });
}

/**
 * Ordena los días del mes por cercanía a la fecha objetivo. Ante la misma
 * distancia se prueba primero el día posterior y luego el anterior.
 */
export function ordenarDiasMesPorProximidad(params: {
  dias: Date[];
  fechaObjetivo: Date;
  periodoAnio: number;
  periodoMes: number;
}): Date[] {
  const objetivo = new Date(
    params.fechaObjetivo.getFullYear(),
    params.fechaObjetivo.getMonth(),
    params.fechaObjetivo.getDate(),
  );
  return params.dias
    .filter(
      (dia) =>
        dia.getFullYear() === params.periodoAnio &&
        dia.getMonth() + 1 === params.periodoMes,
    )
    .sort((a, b) => {
      const distanciaA = Math.abs(+a - +objetivo);
      const distanciaB = Math.abs(+b - +objetivo);
      if (distanciaA !== distanciaB) return distanciaA - distanciaB;
      const aPosterior = +a >= +objetivo;
      const bPosterior = +b >= +objetivo;
      if (aPosterior !== bPosterior) return aPosterior ? -1 : 1;
      return +a - +b;
    });
}

export async function getLimiteMinSemanaPorOperario(params: {
  prisma: PrismaClient;
  conjuntoId: string;
  operarioId: string;
  horariosPorDia: Map<DiaSemana, HorarioDia>;
  fechaReferencia?: Date;
}): Promise<number> {
  const { prisma, operarioId, horariosPorDia, fechaReferencia } = params;

  const op = await prisma.operario.findUnique({
    where: { id: operarioId },
    select: {
      usuario: { select: { jornadaLaboral: true, patronJornada: true } },
    },
  });

  const jornada = (op?.usuario?.jornadaLaboral ?? null) as string | null;
  const patron = (op?.usuario?.patronJornada ?? null) as string | null;
  const ref = fechaReferencia ?? new Date();

  const monday = new Date(ref);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));

  // Si es COMPLETA => capacidad = total del conjunto
  if (jornada === "COMPLETA" || !jornada) {
    let total = 0;
    for (let offset = 0; offset < 7; offset++) {
      const fecha = new Date(monday);
      fecha.setDate(monday.getDate() + offset);
      const ds = dateToDiaSemana(fecha);
      const h = horariosPorDia.get(ds);
      if (!h) continue;
      const disponibilidad = await obtenerDisponibilidadActivaOperarios({
        prisma,
        operariosIds: [operarioId],
        fecha,
      });
      const periodo = disponibilidad.get(operarioId);
      const allowed = allowedIntervalsForUserWithAvailability({
        dia: ds,
        horario: h,
        jornadaLaboral: jornada,
        patronJornada: patron,
        disponibilidad: periodo
            ? {
                trabajaDomingo: periodo.trabajaDomingo,
                diaDescanso: periodo.diaDescanso,
              }
            : null,
      });
      if (allowed.length === 0) {
        continue;
      }
      total += h.endMin - h.startMin;
    }
    const empresaLimite = await prisma.operario.findUnique({
      where: { id: operarioId },
      select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return Math.min(total, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
  }

  // MEDIO_TIEMPO => capacidad = lo que deja el patrón (exacto)
  if (jornada === "MEDIO_TIEMPO") {
    let total = 0;
    for (let offset = 0; offset < 7; offset++) {
      const fecha = new Date(monday);
      fecha.setDate(monday.getDate() + offset);
      const dia = dateToDiaSemana(fecha);
      const h = horariosPorDia.get(dia);
      if (!h) continue;
      const disponibilidad = await obtenerDisponibilidadActivaOperarios({
        prisma,
        operariosIds: [operarioId],
        fecha,
      });
      const allowed = allowedIntervalsForUserWithAvailability({
        dia,
        horario: h,
        jornadaLaboral: jornada,
        patronJornada: patron,
        disponibilidad: disponibilidad.get(operarioId)
            ? {
                trabajaDomingo: disponibilidad.get(operarioId)!.trabajaDomingo,
                diaDescanso: disponibilidad.get(operarioId)!.diaDescanso,
              }
            : null,
      });

      for (const a of allowed) total += a.f - a.i;
    }
    const empresaLimite = await prisma.operario.findUnique({
      where: { id: operarioId },
      select: { empresa: { select: { limiteHorasSemana: true } } },
    });
    return Math.min(total, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
  }

  // Otros casos (por si creces luego)
  let fallback = 0;
  for (const [, h] of horariosPorDia) fallback += h.endMin - h.startMin;
  const empresaLimite = await prisma.operario.findUnique({
    where: { id: operarioId },
    select: { empresa: { select: { limiteHorasSemana: true } } },
  });
  return Math.min(fallback, (empresaLimite?.empresa?.limiteHorasSemana ?? 42) * 60);
}
