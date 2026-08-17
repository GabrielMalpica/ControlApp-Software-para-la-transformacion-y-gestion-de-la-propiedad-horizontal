// src/services/DefinicionTareaPreventivaService.ts

import type { PrismaClient } from "@prisma/client";
import { randomUUID } from "node:crypto";
import {
  Prisma,
  TipoTarea,
  EstadoTarea,
  Frecuencia,
  DiaSemana,
  Rol,
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
import { parseMaquinariaIdsComprometidos } from "../utils/maquinariaNecesidades";
import {
  DIAS_ENTREGA_RECOGIDA,
  calcularRangoReserva,
} from "../utils/reservaMaquinaria";

import type { Bloqueo, HorarioDia } from "../utils/agenda";
import {
  buildAgendaPorOperarioDia,
  buscarHuecoDiaConSplitEarliest,
  findNextValidDay,
  freeFromOccupied,
  getFestivosSet,
  intentarReemplazoPorPrioridadBaja,
  isFestivoDate,
  mergeIntervalos,
  splitMinutes,
  toDateAtMin,
  toMinOfDay,
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
} from "../utils/elementoHierarchy";
import {
  allowedIntervalsForUserWithAvailability,
  diaSemanaFromDate,
  obtenerIntervalosEfectivosProgramacion,
  validarIntervaloProgramacion,
  validarLimiteSemanalOperarios,
  obtenerDisponibilidadActivaOperarios,
  validarOperariosDisponiblesEnFecha,
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
      motivo: "FESTIVO" | "DOMINGO";
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
    };

type ExclusionMotivoTipo =
  | "SIN_CAPACIDAD_P1"
  | "SIN_CANDIDATAS"
  | "SIN_HUECO"
  | "REQUIERE_CONFIRMACION_REEMPLAZO"
  | "FESTIVO_OMITIDO"
  | "REEMPLAZO_PRIORIDAD"
  | "MANUAL_REEMPLAZADA"
  | "MANUAL_ELIMINADA";

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
 * Tope de bloques en que la fase de rescate puede partir una tarea dentro de un mismo dia.
 * Con 3 se cubre el caso tipico "mañana + antes del almuerzo + tarde" sin fragmentar en exceso.
 */
const MAX_BLOQUES_RESCATE_POR_DIA = Number.MAX_SAFE_INTEGER;

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
  operarios: { include: { usuario: true } },
  ubicacion: true,
  elemento: { include: elementoParentChainInclude },
  supervisor: { include: { usuario: true } },
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
  private agendaSchedulerActiva = false;
  private agendaScheduler = new Map<string, IntervaloAgendaScheduler[]>();
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

  private async iniciarAgendaScheduler(params: {
    conjuntoId: string;
    inicio: Date;
    fin: Date;
  }) {
    this.agendaScheduler.clear();
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

    const sinPlanificar = definiciones.filter(
      (def) =>
        !enBorrador.defIds.has(def.id) &&
        !enBorrador.claves.has(claveDefinicionBorrador(def)),
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
      operariosIds: def.operarios.map((o) => o.id),
      operariosNombres: def.operarios
        .map((o) => o.usuario?.nombre ?? "")
        .filter((name) => name.trim().length > 0),
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
      duracionMinutos: tarea.duracionMinutos,
      fechaObjetivo: tarea.fechaInicioOriginal ?? tarea.fechaInicio,
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

  private async validarSlotPreventivaBorrador(params: {
    conjuntoId: string;
    fechaInicio: Date;
    fechaFin: Date;
    operariosIds: string[];
    excluirTareaId?: number;
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

    const inicioEsFestivo = await isFestivoDate({
      prisma: this.prisma,
      fecha: fechaInicio,
      pais: "CO",
    });
    if (inicioEsFestivo) {
      throw new Error("No se permite programar tareas preventivas en festivos.");
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

    const horarios = await this.prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
    const horariosPorDia = new Map<DiaSemana, HorarioDia>();
    for (const h of horarios) {
      horariosPorDia.set(h.dia, {
        startMin: toMin(h.horaApertura),
        endMin: toMin(h.horaCierre),
        descansoStartMin: h.descansoInicio ? toMin(h.descansoInicio) : undefined,
        descansoEndMin: h.descansoFin ? toMin(h.descansoFin) : undefined,
      });
    }

    const inicioMes = new Date(excluida.periodoAnio, excluida.periodoMes - 1, 1, 0, 0, 0, 0);
    const finMes = new Date(excluida.periodoAnio, excluida.periodoMes, 0, 23, 59, 59, 999);
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioMes,
      fin: finMes,
    });

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
      if (festivosSet.has(key)) continue;

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
        festivosSet,
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
      preferida,
      maxBloquesPorDia = 3,
      permitirMultiDia = true,
      validarLimiteSemanal = false,
      incluirPublicadasEnAgenda = true,
      splitSoloPorDescanso = false,
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

      const horario = horariosPorDia.get(dateToDiaSemana(dia));
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
   * Devuelve todos los días hábiles del mes objetivo. El día previsto conserva
   * la primera oportunidad y luego se priorizan las jornadas más aprovechadas.
   */
  private async diasMesPorAprovechamiento(params: {
    conjuntoId: string;
    fechaObjetivo: Date;
    periodoAnio: number;
    periodoMes: number;
    operariosIds: string[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
  }): Promise<Date[]> {
    const inicio = new Date(params.periodoAnio, params.periodoMes - 1, 1);
    const fin = new Date(params.periodoAnio, params.periodoMes, 0);

    const candidatos = enumerateDays(inicio, fin).filter(
      (dia) =>
        dia.getFullYear() === params.periodoAnio &&
        dia.getMonth() + 1 === params.periodoMes &&
        !params.festivosSet.has(dayKey(dia)) &&
        params.horariosPorDia.has(dateToDiaSemana(dia)),
    );
    const cargas = await this.cargaOperariosEnDias({
      conjuntoId: params.conjuntoId,
      dias: candidatos,
      operariosIds: params.operariosIds,
      horariosPorDia: params.horariosPorDia,
    });
    const conCarga = candidatos.map((dia) => ({
      dia,
      carga: cargas.get(dayKey(dia)) ?? 0,
    }));
    const objetivoKey = dayKey(params.fechaObjetivo);

    conCarga.sort((a, b) => {
      const aObjetivo = dayKey(a.dia) === objetivoKey;
      const bObjetivo = dayKey(b.dia) === objetivoKey;
      if (aObjetivo !== bObjetivo) return aObjetivo ? -1 : 1;
      if (a.carga !== b.carga) return b.carga - a.carga;

      const distanciaA = Math.abs(+a.dia - +params.fechaObjetivo);
      const distanciaB = Math.abs(+b.dia - +params.fechaObjetivo);
      if (distanciaA !== distanciaB) return distanciaA - distanciaB;

      // A igual distancia se usa primero el día futuro y luego el anterior.
      const aFuturo = +a.dia >= +params.fechaObjetivo;
      const bFuturo = +b.dia >= +params.fechaObjetivo;
      if (aFuturo !== bFuturo) return aFuturo ? -1 : 1;
      return +a.dia - +b.dia;
    });

    return conCarga.map((item) => item.dia);
  }

  /** Elige el día que requiere menos fragmentos y luego el de mayor carga. */
  private async construirMejorPlanEnDias(params: {
    conjuntoId: string;
    duracionMinutos: number;
    operariosIds: string[];
    dias: Date[];
    horariosPorDia: Map<DiaSemana, HorarioDia>;
    festivosSet: Set<string>;
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
        maxBloquesPorDia: MAX_BLOQUES_RESCATE_POR_DIA,
        permitirMultiDia: false,
        validarLimiteSemanal: true,
        incluirPublicadasEnAgenda: params.incluirPublicadasEnAgenda,
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
      maxBloquesPorDia: Number.MAX_SAFE_INTEGER,
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
      });
    }

    const grupoPlanId = bloquesOrdenados.length > 1
      ? `EXC-${excluida.id}-${Date.now().toString(36)}`
      : null;

    const planes = await this.cargarPlanesRecursosExcluida(excluida);

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

  private async crearConCliente(
    client: PrismaClient | Prisma.TransactionClient,
    payload: unknown,
  ) {
    const dto = CrearDefinicionPreventivaDTO.parse(payload);
    this.validarProgramacionFrecuencia(dto);

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

    // Operarios: operariosIds > responsableSugeridoId
    if (dto.operariosIds?.length) {
      (data as any).operarios = {
        connect: dto.operariosIds.map((id) => ({ id })),
      };
    } else if (dto.responsableSugeridoId != null) {
      (data as any).operarios = {
        connect: { id: dto.responsableSugeridoId },
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
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },
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
        operarios: { include: { usuario: true } },
        supervisor: { include: { usuario: true } },
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

    const actual: any = await this.prisma.definicionTareaPreventiva.findUnique({
      where: { id },
      select: {
        frecuencia: true,
        diaSemanaProgramado: true,
        diaMesProgramado: true,
        fechasProgramadasJson: true,
      } as any,
    });
    if (!actual) {
      throw new Error("Definición no encontrada para este conjunto.");
    }

    this.validarProgramacionFrecuencia({
      frecuencia: dto.frecuencia ?? actual.frecuencia,
      diaSemanaProgramado:
        dto.diaSemanaProgramado === undefined
          ? actual.diaSemanaProgramado
          : dto.diaSemanaProgramado,
      diaMesProgramado:
        dto.diaMesProgramado === undefined ? actual.diaMesProgramado : dto.diaMesProgramado,
      fechasProgramadasJson:
        dto.fechasProgramadasJson === undefined
          ? ((actual.fechasProgramadasJson as string[] | null | undefined) ?? null)
          : dto.fechasProgramadasJson,
    });

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

    // relaciones operarios
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
      include: { operarios: true },
    });

    if (!original || !original.borrador || original.conjuntoId !== conjuntoId) {
      throw new Error(
        "Tarea no encontrada, no es borrador o no pertenece a este conjunto.",
      );
    }
    if (original.tipo !== TipoTarea.PREVENTIVA) {
      throw new Error("Solo se pueden dividir tareas preventivas en borrador.");
    }

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
      include: { operarios: { select: { id: true } } },
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

    // rango del mes + buffer
    const month0 = mes - 1;
    const inicioMes = new Date(anio, month0, 1, 0, 0, 0, 0);
    const finMes = new Date(anio, month0 + 1, 0, 23, 59, 59, 999);

    const bufferDias = 20;
    const inicioRangoFestivos = new Date(inicioMes);
    inicioRangoFestivos.setDate(inicioRangoFestivos.getDate() - bufferDias);

    const finRangoFestivos = new Date(finMes);
    finRangoFestivos.setDate(finRangoFestivos.getDate() + bufferDias);

    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioRangoFestivos,
      fin: finRangoFestivos,
    });

    const reservasResp = await this.crearReservasPlanificadasParaTareas({
      conjuntoId,
      tareas: borradores.map((t) => ({
        id: t.id,
        grupoPlanId: t.grupoPlanId ?? null,
        fechaInicio: t.fechaInicio,
        fechaFin: t.fechaFin,
        maquinariaPlanJson: t.maquinariaPlanJson,
        descripcion: t.descripcion,
      })),
      diasEntregaRecogida: DIAS_ENTREGA_RECOGIDA,
      excluirTareaIds: [],
      festivosSet,
    });

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
        reservas: reservasResp?.creadas ?? 0,
        tareaIds: borradores.map((tarea: any) => tarea.id),
      },
    });

    return {
      ok: true,
      publicadas: borradores.length,
      reservas: reservasResp?.creadas ?? 0,
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
    this.agendaSchedulerActiva = false;
    this.agendaScheduler.clear();
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
        supervisor: true,
        ubicacion: { select: { nombre: true } },
        elemento: { include: elementoParentChainInclude },
      },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });

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
      if (a.operarios.length !== b.operarios.length) {
        return b.operarios.length - a.operarios.length;
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

    const resolverDiaProgramable = (start: Date, prioridad: number) => {
      return findNextValidDay({
        start,
        periodoAnio,
        periodoMes,
        prioridad,
        horariosPorDia,
        festivosSet,
      });
    };

    // P1 y P2 conservan la fecha contemplada como referencia aunque sea
    // festivo o no tenga jornada. Sus fases de rescate recorren después todos
    // los días válidos del mes, hacia adelante y hacia atrás.
    const resolverDiaObjetivo = (start: Date, prioridad: number) => {
      if (prioridad !== 1 && prioridad !== 2) {
        return resolverDiaProgramable(start, prioridad);
      }
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

    // 6️⃣ Fases de cobertura: P1/P2 conservan precedencia real; después cada
    // definición P3 recibe una primera oportunidad antes de sus repeticiones.
    const p3 = defs.filter((def) => Number((def as any).prioridad ?? 2) === 3);
    const fases: Array<{
      definiciones: typeof defs;
      coberturaP3: "TODAS" | "PRIMERA" | "RESTANTES";
    }> = [
      {
        definiciones: defs.filter(
          (def) => Number((def as any).prioridad ?? 2) !== 3,
        ),
        coberturaP3: "TODAS",
      },
      { definiciones: p3, coberturaP3: "PRIMERA" },
      { definiciones: p3, coberturaP3: "RESTANTES" },
    ];

    for (const fase of fases) {
      for (const def of fase.definiciones) {
      const prioridad = Number((def as any).prioridad ?? 2);
      const operariosIds = def.operarios.map((o) => o.id);

      // evitar duplicar si ya fue publicada
      const clavePublicada = `${def.descripcion}|${def.ubicacionId}|${def.elementoId}|${def.frecuencia ?? ""}`;
      if (
        definicionesPublicadas.has(def.id) ||
        clavesPublicadas.has(clavePublicada)
      ) {
        continue;
      }

      // En modo CONSERVAR, lo que ya esta en el borrador no se vuelve a planificar.
      if (
        definicionesYaEnBorrador != null &&
        (definicionesYaEnBorrador.defIds.has(def.id) ||
          definicionesYaEnBorrador.claves.has(claveDefinicionBorrador(def)))
      ) {
        continue;
      }

      // días según frecuencia
      const diasBase = pickDaysByFrecuencia(fechasDelMes, def);

      // Cada fecha esperada se conserva aunque no tenga horario; el intento de
      // programación decidirá si se mueve o queda con una causa explícita.
      const diasValidos =
        fase.coberturaP3 === "PRIMERA"
          ? diasBase.slice(0, 1)
          : fase.coberturaP3 === "RESTANTES"
            ? diasBase.slice(1)
            : diasBase;

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

        const diaProgramable = resolverDiaObjetivo(diaBase, prioridad);
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
          const diaBaseEsFestivo = festivosSet.has(dayKey(diaBase));
          const diaBaseEsDomingo =
            dateToDiaSemana(diaBase) === DiaSemana.DOMINGO;
          if (diaBaseEsFestivo || diaBaseEsDomingo) {
            const mensaje = diaBaseEsDomingo
              ? "La tarea cae en domingo y no se programo en el periodo."
              : "La tarea cae en festivo y no se programo en el periodo.";
            novedades.push({
              tipo: "FESTIVO_OMITIDO",
              defId: def.id,
              descripcion: def.descripcion,
              prioridad,
              fecha: dayKey(diaBase),
              motivo: diaBaseEsDomingo ? "DOMINGO" : "FESTIVO",
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
              motivoTipo: "FESTIVO_OMITIDO",
              motivoMensaje: mensaje,
              metadataJson: {
                motivo: diaBaseEsDomingo ? "DOMINGO" : "FESTIVO",
              },
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

        // ✅ log: cayó en festivo/domingo y se movió
        const diaBaseEsFestivo = festivosSet.has(dayKey(diaBase));
        const diaBaseEsDomingo = dateToDiaSemana(diaBase) === DiaSemana.DOMINGO;
        if (
          (diaBaseEsFestivo || diaBaseEsDomingo) &&
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

        // ✅ Duración REAL
        // ✅ diasParaCompletar: divide minutos en N días
        const diasParaCompletar = Math.max(
          1,
          Number((def as any).diasParaCompletar ?? 1),
        );
        const partesMin = splitMinutes(durMinTotal, diasParaCompletar);

        // Grupo si multi-día
        const grupoPlanId =
          partesMin.length > 1
            ? `BOR-${def.id}-${periodoAnio}-${periodoMes}-${Math.random()
                .toString(36)
                .slice(2, 8)}`
            : null;

        const totalBloquesEsperados = partesMin.length;
        let bloqueIndexCursor = 1;

        // cursor de día para las partes
        let cursorDia = new Date(diaProgramable);

        for (let p = 0; p < partesMin.length; p++) {
          const durMinParte = partesMin[p];

          let diaParte = resolverDiaObjetivo(cursorDia, prioridad);
          if (!diaParte) {
            if (prioridad === 1) {
              const mensaje =
                `No hay un día hábil restante para completar la tarea obligatoria '${def.descripcion}'.`;
              novedades.push({
                tipo: "SIN_HUECO",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: dayKey(cursorDia),
                mensaje,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                ocurrenciaPlanId,
                defId: def.id,
                fechaObjetivo: cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "SIN_CAPACIDAD_P1",
                motivoMensaje: mensaje,
              });
            }
            break;
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
            const esFestivo = festivosSet.has(diaParteKey);
            const disponibilidadOperarios = operariosIds.length
              ? await this.disponibilidadScheduler({
                  fecha: diaParte,
                  operariosIds,
                })
              : { ok: true, noDisponibles: [] as string[] };

            // Festivo, operario no disponible o dia sin horario: se abandona la fase A
            // y se delega en la fase de rescate, que barre el resto del periodo.
            if (esFestivo || !disponibilidadOperarios.ok) break;

            const horario = horariosPorDia.get(dateToDiaSemana(diaParte));
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
              maxBloques: prioridad === 1 ? 2 : Number.MAX_SAFE_INTEGER,
              splitSoloPorDescanso: prioridad === 1,
            });

            if (bloquesFound) {
              // Todas las prioridades respetan la capacidad semanal real.
              // Si una P1 no cabe, continúa con el rescate dentro del mes.
              const pasaLimite = await this.cabeEnLimiteSemanal({
                conjuntoId,
                operariosIds,
                fechaReferencia: toDateAtMin(diaParte, bloquesFound[0].i),
                minutosAdicionales: durMinParte,
                horariosPorDia,
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
            const diasP1 = ordenarDiasMesPorProximidad({
              dias: enumerateDays(inicioMes, finMes).filter(
                (dia) =>
                  !festivosSet.has(dayKey(dia)) &&
                  horariosPorDia.has(dateToDiaSemana(dia)),
              ),
              fechaObjetivo: diaObjetivoParte,
              periodoAnio,
              periodoMes,
            });

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
                horariosPorDia,
                festivosSet,
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

                const horario = horariosPorDia.get(
                  dateToDiaSemana(diaAlternativo),
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
          // Fase B - rescate mensual para P2/P3. P1 queda anclada a su fecha
          // prevista (o al siguiente hábil cuando la prevista es festiva).
          // ============================================================
          if (!agendada && prioridad !== 1) {
            const diasRescate = await this.diasMesPorAprovechamiento({
              conjuntoId,
              fechaObjetivo: diaObjetivoParte,
              periodoAnio,
              periodoMes,
              operariosIds,
              horariosPorDia,
              festivosSet,
            });
            diasMesEvaluados = diasRescate;

            if (diasRescate.length) {
              // 1) elegir el día que deja menos fragmentación y completa mejor
              // las jornadas ya ocupadas de todos los operarios requeridos.
              let planRescate = await this.construirMejorPlanEnDias({
                conjuntoId,
                duracionMinutos: durMinParte,
                operariosIds,
                dias: diasRescate,
                horariosPorDia,
                festivosSet,
                incluirPublicadasEnAgenda,
              });

              // 2) si ningun dia la aloja entera, se reparte entre varios dias
              if (!planRescate.length) {
                planRescate = await this.construirPlanEnRango({
                  conjuntoId,
                  duracionMinutos: durMinParte,
                  operariosIds,
                  dias: diasRescate,
                  horariosPorDia,
                  festivosSet,
                  maxBloquesPorDia: MAX_BLOQUES_RESCATE_POR_DIA,
                  permitirMultiDia: true,
                  validarLimiteSemanal: true,
                  incluirPublicadasEnAgenda,
                });
              }

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

              const horario = horariosPorDia.get(
                dateToDiaSemana(diaAlternativo),
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
                incluirBorradorEnAgenda: true,
                incluirPublicadasEnAgenda,
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

          // mover cursor al siguiente día (para la siguiente parte)
          cursorDia = new Date(diaParte ?? cursorDia);
          cursorDia.setDate(cursorDia.getDate() + 1);

          if (!agendada) break;
        }
      }
    }
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
    });

    if (fechaInicio) {
      const inicioEsFestivo = await isFestivoDate({
        prisma: this.prisma,
        fecha: fechaInicio,
        pais: "CO",
      });
      if (inicioEsFestivo) {
        throw new Error("No se permite programar tareas preventivas en festivos.");
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

    if (fechaInicio && fechaFin) {
      const maqIds = Array.from(new Set(parseMaquinariaIdsComprometidos(tarea.maquinariaPlanJson)));
      if (maqIds.length) {
        const disponibilidad = await this.listarMaquinariaDisponible({
          conjuntoId,
          fechaInicioUso: fechaInicio,
          fechaFinUso: fechaFin,
          excluirTareaId: tareaId,
          excluirGrupoPlanId: tarea.grupoPlanId ?? undefined,
        });
        if (disponibilidad.ok) {
          const conflictos = (disponibilidad.conflictos ?? []).filter((item) =>
            maqIds.includes(item.maquinariaId),
          );
          if (conflictos.length) {
            const primero = conflictos[0];
            throw buildMaquinariaNoDisponibleError({
              maquinariaId: primero.maquinariaId,
              maquinaNombre: primero.maquinaNombre ?? undefined,
              conflictos,
            });
          }
        }
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
    });

    const grupoPlanId = `EXC-MANUAL-${excluida.id}`;
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

    // El usuario puede estar viendo solo las tareas de un operario. Si una de
    // ellas es compartida, el nuevo horario también puede afectar la agenda de
    // otros operarios. Se amplía el conjunto de forma transitiva hasta incluir
    // todas las tareas del día conectadas por un operario en común.
    const idsInvolucrados = new Set(idsSolicitados);
    const operariosInvolucrados = new Set<string>();
    for (const id of idsSolicitados) {
      for (const operario of tareasPorId.get(id)?.operarios ?? []) {
        operariosInvolucrados.add(operario.id);
      }
    }

    let seAmplio = true;
    while (seAmplio) {
      seAmplio = false;
      for (const tarea of tareasDiaDisponibles) {
        if (idsInvolucrados.has(tarea.id)) continue;
        if (
          !tarea.operarios.some((operario) =>
            operariosInvolucrados.has(operario.id),
          )
        ) {
          continue;
        }
        idsInvolucrados.add(tarea.id);
        for (const operario of tarea.operarios) {
          operariosInvolucrados.add(operario.id);
        }
        seAmplio = true;
      }
    }

    const tareasInvolucradas = tareasDiaDisponibles.filter((tarea) =>
      idsInvolucrados.has(tarea.id),
    );
    const ordenSolicitado = dto.tareaIds.map((id) => tareasPorId.get(id)!);
    let indiceSolicitado = 0;
    const seleccionOrdenada = tareasInvolucradas.map((tarea) =>
      idsSolicitados.has(tarea.id)
        ? ordenSolicitado[indiceSolicitado++]
        : tarea,
    );
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
    const ventanasTrabajo = construirVentanasTrabajoDia(horario);
    const ventanasReordenamiento = construirVentanasOcupadasReordenamiento({
      tareas: tareasInvolucradas,
      ventanasTrabajo,
    });
    const primeraVentana = ventanasReordenamiento[0] ?? ventanasTrabajo[0];
    if (!primeraVentana) {
      throw new Error("No hay ventanas disponibles para reordenar las tareas del día.");
    }

    const actualizaciones: Array<{ id: number; fechaInicio: Date; fechaFin: Date }> = [];
    const recreaciones: Array<{
      original: (typeof tareasInvolucradas)[number];
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
    let cursor = toDateAtMin(dto.fecha, primeraVentana.i);
    for (const tarea of seleccionOrdenada) {
      const duracion = calcularDuracionLaboralReordenamiento({
        tarea,
        horario,
      });
      let segmentos: Array<{ fechaInicio: Date; fechaFin: Date }>;
      try {
        segmentos =
          intentarDistribuirDuracionReordenamiento({
            fecha: dto.fecha,
            ventanas: ventanasReordenamiento,
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
      } catch (error) {
        const detalle = error instanceof Error ? error.message : String(error);
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
        throw new Error("No se permite programar tareas preventivas en festivos.");
      }

      const operariosIds = tarea.operarios.map((item) => item.id);
      for (const segmento of segmentos) {
        const validacion = await validarIntervaloProgramacion({
          prisma: this.prisma,
          conjuntoId: dto.conjuntoId,
          fechaInicio: segmento.fechaInicio,
          fechaFin: segmento.fechaFin,
          operariosIds,
        });
        if (!validacion.ok) {
          throw new Error(
            `No se pudo ubicar la tarea "${tarea.descripcion}": ${validacion.mensaje}` +
              contextoInvolucrados,
          );
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

        for (const segmento of segmentos) {
          const solape = await this.prisma.tarea.findFirst({
            where: {
              conjuntoId: dto.conjuntoId,
              borrador: true,
              id: { notIn: Array.from(idsInvolucrados) },
              estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
              NOT: {
                estado: "NO_COMPLETADA" as any,
                reprogramada: true,
                reprogramadaPorTareaId: { not: null },
              },
              fechaInicio: { lt: segmento.fechaFin },
              fechaFin: { gt: segmento.fechaInicio },
              operarios: { some: { id: { in: operariosIds } } },
            },
            select: {
              id: true,
              descripcion: true,
              fechaInicio: true,
              fechaFin: true,
              operarios: {
                where: { id: { in: operariosIds } },
                select: {
                  id: true,
                  usuario: { select: { nombre: true } },
                },
              },
            },
          });
          if (solape) {
            throw new Error(
              construirMensajeSolapeReordenamiento({
                tareaActual: tarea,
                tareaSolapada: solape,
                segmentoIntentado: segmento,
              }),
            );
          }
        }
      }

      if (segmentos.length === 1) {
        actualizaciones.push({ id: tarea.id, fechaInicio, fechaFin });
      } else {
        recreaciones.push({ original: tarea, segmentos });
      }
      cursor = fechaFin;
    }

    await this.prisma.$transaction(async (tx) => {
      for (const item of actualizaciones) {
        await tx.tarea.update({
          where: { id: item.id },
          data: {
            fechaInicio: item.fechaInicio,
            fechaFin: item.fechaFin,
          },
        });
      }

      for (const item of recreaciones) {
        await tx.tarea.delete({ where: { id: item.original.id } });

        for (const segmento of item.segmentos) {
          await tx.tarea.create({
            data: buildTareaBorradorCreateData(
              item.original,
              segmento.fechaInicio,
              segmento.fechaFin,
            ),
          });
        }
      }
    });

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
      reordenadas: actualizaciones.length + recreaciones.length,
      divididas: recreaciones.length,
      ajustadasPorDependencia:
        tareasInvolucradas.length - idsSolicitados.size,
      operariosInvolucrados: nombresOperariosInvolucrados,
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

    const horarios = await this.prisma.conjuntoHorario.findMany({ where: { conjuntoId } });
    const horariosPorDia = new Map<DiaSemana, HorarioDia>();
    for (const h of horarios) {
      horariosPorDia.set(h.dia, {
        startMin: toMin(h.horaApertura),
        endMin: toMin(h.horaCierre),
        descansoStartMin: h.descansoInicio ? toMin(h.descansoInicio) : undefined,
        descansoEndMin: h.descansoFin ? toMin(h.descansoFin) : undefined,
      });
    }

    const inicioBase = new Date(tarea.fechaInicioOriginal ?? tarea.fechaInicio);
    const finBusqueda = new Date(inicioBase);
    finBusqueda.setDate(finBusqueda.getDate() + 7);
    const festivosSet = await getFestivosSet({
      prisma: this.prisma,
      pais: "CO",
      inicio: inicioBase,
      fin: finBusqueda,
    });

    const operariosIds = tarea.operarios.map((o) => o.id);
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
        periodoAnio: true,
        periodoMes: true,
      },
    });
    if (!tarea) {
      throw new Error("Bloque no encontrado o no es borrador preventivo.");
    }

    await this.crearExcluidaDesdeTarea({
      tareaId,
      motivoTipo: "MANUAL_ELIMINADA",
      motivoMensaje: "La tarea fue retirada manualmente del borrador.",
    });

    await this.auditarTarea({
      tareaId,
      conjuntoId,
      accion: AccionAuditoria.ELIMINAR,
      descripcion: `Se retiro manualmente la tarea '${tarea.descripcion}' del borrador y paso a excluidas.`,
      periodoAnio: tarea.periodoAnio,
      periodoMes: tarea.periodoMes,
      datosAntes: {
        fechaInicio: tarea.fechaInicio,
        fechaFin: tarea.fechaFin,
      },
    });

    await this.prisma.tarea.delete({ where: { id: tareaId } });
  }

  async listarBorrador(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;

    return this.prisma.tarea.findMany({
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

function distribuirDuracionReordenamiento(params: {
  fecha: Date;
  ventanas: Intervalo[];
  inicioCursor: Date;
  duracionMinutos: number;
  horario: HorarioDia;
}): Array<{ fechaInicio: Date; fechaFin: Date }> {
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

  throw new Error(
    "No se pudo reordenar porque el nuevo orden no cabe dentro de la jornada laboral del día.",
  );
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
    if (
      error instanceof Error &&
      error.message ===
        "No se pudo reordenar porque el nuevo orden no cabe dentro de la jornada laboral del día."
    ) {
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
    include: { usuario: true },
  });

  return op?.usuario?.nombre ?? `Operario ${idStr}`;
}

function construirMensajeSolapeReordenamiento(params: {
  tareaActual: { id: number; descripcion?: string | null };
  tareaSolapada: {
    id: number;
    descripcion?: string | null;
    fechaInicio: Date;
    fechaFin: Date;
    operarios: Array<{ id: string; usuario?: { nombre?: string | null } | null }>;
  };
  segmentoIntentado: { fechaInicio: Date; fechaFin: Date };
}): string {
  const { tareaActual, tareaSolapada, segmentoIntentado } = params;
  const inicioSolape = new Date(
    Math.max(segmentoIntentado.fechaInicio.getTime(), tareaSolapada.fechaInicio.getTime()),
  );
  const finSolape = new Date(
    Math.min(segmentoIntentado.fechaFin.getTime(), tareaSolapada.fechaFin.getTime()),
  );

  const nombresOperarios = Array.from(
    new Set(
      tareaSolapada.operarios
        .map((operario) => operario.usuario?.nombre?.trim() || `Operario ${operario.id}`)
        .filter(Boolean),
    ),
  );
  const operariosTexto =
    nombresOperarios.length <= 1
      ? nombresOperarios[0] ?? "seleccionado"
      : nombresOperarios.join(", ");
  const tareaActualTexto = tareaActual.descripcion?.trim() || `tarea ${tareaActual.id}`;
  const tareaSolapadaTexto =
    tareaSolapada.descripcion?.trim() || `tarea ${tareaSolapada.id}`;

  return `No se pudo reordenar la tarea "${tareaActualTexto}" porque se solapa en la agenda de ${operariosTexto} con "${tareaSolapadaTexto}" entre ${formatHoraLocal(inicioSolape)} y ${formatHoraLocal(finSolape)} del ${formatFechaLocal(inicioSolape)}.`;
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
