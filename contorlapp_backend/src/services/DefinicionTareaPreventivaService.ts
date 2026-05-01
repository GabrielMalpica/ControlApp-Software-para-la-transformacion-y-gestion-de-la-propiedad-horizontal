// src/services/DefinicionTareaPreventivaService.ts

import type { PrismaClient } from "@prisma/client";
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
  calcularMinutosEstimados,
} from "../model/DefinicionTareaPreventiva";

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
  siguienteDiaHabil,
  splitMinutes,
  toDateAtMin,
  toMinOfDay,
  toMin,
  ymdLocal,
} from "../utils/schedulerUtils";

import { buildMaquinariaNoDisponibleError } from "../utils/errorFormat";
import {
  construirRutaElemento,
  elementoParentChainInclude,
} from "../utils/elementoHierarchy";
import {
  allowedIntervalsForUserWithAvailability,
  diaSemanaFromDate,
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
    };

type ExclusionMotivoTipo =
  | "SIN_CANDIDATAS"
  | "SIN_HUECO"
  | "REQUIERE_CONFIRMACION_REEMPLAZO"
  | "FESTIVO_OMITIDO"
  | "MANUAL_REEMPLAZADA"
  | "MANUAL_ELIMINADA";

type ExcluidaSnapshot = {
  conjuntoId: string;
  periodoAnio: number;
  periodoMes: number;
  defId?: number | null;
  origenTareaId?: number | null;
  tareaProgramadaId?: number | null;
  descripcion: string;
  frecuencia?: Frecuencia | null;
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
  aplicarADefinicion: z.boolean().optional().default(false),
});

const ReasignarOperarioExcluidaDTO = z.object({
  conjuntoId: z.string().min(3),
  excluidaId: z.number().int().positive(),
  nuevoOperarioId: z.coerce.number().int().positive(),
  aplicarADefinicion: z.boolean().optional().default(false),
});

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

/* =========================================================
 * Service
 * ======================================================= */

export class DefinicionTareaPreventivaService {
  constructor(private prisma: PrismaClient) {}

  private async resolverSupervisorId(supervisorId: number): Promise<string> {
    const sid = supervisorId.toString();

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
        metadataJson: params.metadataJson,
      },
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
        descripcion: snapshot.descripcion,
        frecuencia: snapshot.frecuencia ?? null,
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
      detalle: snapshot.motivoMensaje ?? undefined,
      excluidaId: created.id,
      tareaId: snapshot.tareaProgramadaId ?? snapshot.origenTareaId ?? null,
      metadataJson: snapshot.metadataJson,
    });

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
  }) {
    const def = await this.cargarSnapshotDefinicion(params.defId, params.conjuntoId);
    if (!def) return null;

    return this.crearExcluida({
      conjuntoId: params.conjuntoId,
      periodoAnio: params.periodoAnio,
      periodoMes: params.periodoMes,
      defId: def.id,
      descripcion: def.descripcion,
      frecuencia: def.frecuencia,
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
      descripcion: tarea.descripcion,
      frecuencia: tarea.frecuencia,
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
          `Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`,
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
    const { conjuntoId, excluida, fechas, horariosPorDia, festivosSet, preferida, startIndex } = params;
    if (startIndex < 0 || startIndex >= fechas.length) return [];

    let restante = excluida.duracionMinutos;
    const plan: BloqueProgramacion[] = [];

    for (let idx = startIndex; idx < fechas.length && restante > 0; idx++) {
      const dia = fechas[idx];
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
          bloqueos.map((bloqueo) => ({ i: bloqueo.startMin, f: bloqueo.endMin })),
        );
      }

      const blocked = mergeIntervalos([
        ...ocupadosGlobal,
        ...bloqueos.map((bloqueo) => ({ i: bloqueo.startMin, f: bloqueo.endMin })),
      ]);
      const libres = freeFromOccupied(horario.startMin, horario.endMin, blocked);
      const desiredStartMin = key === dayKey(preferida)
        ? Math.max(horario.startMin, toMinOfDay(preferida))
        : horario.startMin;

      for (const libre of libres) {
        const inicioMin = Math.max(libre.i, desiredStartMin);
        const capacidad = libre.f - inicioMin;
        if (capacidad <= 0) continue;

        const tomar = Math.min(capacidad, restante);
        const fechaInicio = toDateAtMin(dia, inicioMin);
        const fechaFin = toDateAtMin(dia, inicioMin + tomar);

        try {
          await this.validarSlotPreventivaBorrador({
            conjuntoId,
            fechaInicio,
            fechaFin,
            operariosIds: excluida.operariosIds,
          });
        } catch {
          continue;
        }

        plan.push({ fechaInicio, fechaFin });
        restante -= tomar;
        if (restante <= 0) break;
      }
    }

    return restante <= 0 && plan.length > 1 ? plan : [];
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
          metadataJson: {
            bloques: bloquesOrdenados.map((bloque) => ({
              fechaInicio: bloque.fechaInicio.toISOString(),
              fechaFin: bloque.fechaFin.toISOString(),
            })),
          },
        },
      });

      return creadas;
    });

    return created;
  }

  /* =========================
   * CRUD BÁSICO
   * ======================= */

  async crear(payload: unknown) {
    const dto = CrearDefinicionPreventivaDTO.parse(payload);

    const supervisorIdResuelto =
      dto.supervisorId != null
        ? await this.resolverSupervisorId(dto.supervisorId)
        : null;

    const duracionMinutosFija =
      dto.duracionMinutosFija ??
      (dto.duracionHorasFija != null
        ? Math.max(1, Math.round(Number(dto.duracionHorasFija) * 60))
        : null);

    const data: Prisma.DefinicionTareaPreventivaCreateInput = {
      conjunto: { connect: { nit: dto.conjuntoId } },
      ubicacion: { connect: { id: dto.ubicacionId } },
      elemento: { connect: { id: dto.elementoId } },

      descripcion: dto.descripcion,
      frecuencia: dto.frecuencia,
      prioridad: dto.prioridad ?? 2,

      diaSemanaProgramado: dto.diaSemanaProgramado ?? null,
      diaMesProgramado: dto.diaMesProgramado ?? null,

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
        connect: dto.operariosIds.map((id) => ({ id: id.toString() })),
      };
    } else if (dto.responsableSugeridoId != null) {
      (data as any).operarios = {
        connect: { id: dto.responsableSugeridoId.toString() },
      };
    }

    return this.prisma.definicionTareaPreventiva.create({ data });
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

    // recalcular duración si vienen campos
    const durMinFija =
      (dto as any).duracionMinutosFija === undefined &&
      (dto as any).duracionHorasFija === undefined
        ? undefined
        : ((dto as any).duracionMinutosFija ??
          ((dto as any).duracionHorasFija != null
            ? Math.round(Number((dto as any).duracionHorasFija) * 60)
            : null));

    const data: Prisma.DefinicionTareaPreventivaUpdateInput = {
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

    const { creadas, novedades } = await this.generarBorradorMensual({
      conjuntoId: dto.conjuntoId,
      periodoAnio: dto.anio,
      periodoMes: dto.mes,
      tamanoBloqueMinutos,
      paisFestivos: "CO",
      incluirPublicadasEnAgenda: true,
      confirmacionesReemplazo: dto.confirmacionesReemplazo,
    });

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

    return this.prisma.$transaction(async (tx) => {
      await tx.tarea.delete({ where: { id: tareaId } });

      const base: any = {
        descripcion: original.descripcion,
        estado: EstadoTarea.ASIGNADA,
        tipo: TipoTarea.PREVENTIVA,
        frecuencia: original.frecuencia,
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
  }

  async publicarCronograma(params: {
    conjuntoId: string;
    anio: number;
    mes: number;
  }) {
    const { conjuntoId, anio, mes } = params;

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
      diasEntregaRecogida: new Set([1, 3, 6]), // L, X, S
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

    const excluidasEliminadas = await this.prisma.preventivaExcluidaBorrador.deleteMany({
      where: { conjuntoId, periodoAnio: anio, periodoMes: mes },
    });

    return {
      ok: true,
      publicadas: borradores.length,
      reservas: reservasResp?.creadas ?? 0,
      excluidasDescartadas: excluidasEliminadas.count,
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
  }): Promise<{ creadas: number; novedades: NovedadCronograma[] }> {
    const {
      conjuntoId,
      periodoAnio,
      periodoMes,
      tamanoBloqueMinutos = 60,
      paisFestivos = "CO",
      incluirPublicadasEnAgenda = true,
      confirmacionesReemplazo = [],
    } = params;

    const novedades: NovedadCronograma[] = [];
    const confirmacionesMap = new Map<
      string,
      { aceptar: boolean; candidataId?: number; reprogramarReemplazada?: boolean }
    >();
    const keyConfirmacion = (
      defId: number,
      fecha: string,
      prioridadSolicitante: number,
      prioridadObjetivo: number,
    ) => `${defId}|${fecha}|${prioridadSolicitante}|${prioridadObjetivo}`;

    for (const c of confirmacionesReemplazo) {
      if (!c?.defId || !c?.fecha) continue;
      confirmacionesMap.set(
        keyConfirmacion(
          Number(c.defId),
          String(c.fecha),
          Number(c.prioridadSolicitante ?? 0),
          Number(c.prioridadObjetivo ?? 0),
        ),
        {
          aceptar: Boolean(c.aceptar),
          candidataId:
            c.candidataId != null && Number.isFinite(Number(c.candidataId))
              ? Number(c.candidataId)
              : undefined,
          reprogramarReemplazada:
            c.reprogramarReemplazada == null
              ? undefined
              : Boolean(c.reprogramarReemplazada),
        },
      );
    }

    const obtenerConfirmacion = (args: {
      defId: number;
      fecha: string;
      prioridadSolicitante: number;
      prioridadObjetivo: number;
    }) =>
      confirmacionesMap.get(
        keyConfirmacion(
          args.defId,
          args.fecha,
          args.prioridadSolicitante,
          args.prioridadObjetivo,
        ),
      );

    // 1️⃣ Definiciones activas
    const defs = await this.prisma.definicionTareaPreventiva.findMany({
      where: { conjuntoId, activo: true },
      include: { operarios: true, supervisor: true },
      orderBy: [{ prioridad: "asc" }, { id: "asc" }],
    });

    if (!defs.length) return { creadas: 0, novedades };

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

    const listarCandidatasPorPrioridadDia = async (
      fechaDia: Date,
      prioridades: Array<2 | 3>,
    ): Promise<number[]> => {
      if (!prioridades.length) return [];

      const ini = new Date(
        fechaDia.getFullYear(),
        fechaDia.getMonth(),
        fechaDia.getDate(),
        0,
        0,
        0,
        0,
      );
      const fin = new Date(
        fechaDia.getFullYear(),
        fechaDia.getMonth(),
        fechaDia.getDate(),
        23,
        59,
        59,
        999,
      );

      const rows = await this.prisma.tarea.findMany({
        where: {
          conjuntoId,
          fechaInicio: { lte: fin },
          fechaFin: { gte: ini },
          estado: { notIn: ["PENDIENTE_REPROGRAMACION"] as any },
          prioridad: { in: prioridades },
        },
        select: { id: true },
        orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }, { id: "asc" }],
      });

      return rows.map((r) => r.id);
    };

    // 5️⃣ Limpiar borradores previos
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

    // ✅ Cache de límite semanal por operario (para no recalcular siempre)
    const limitePorOperario = new Map<string, number>();

    let creadas = 0;

    // 6️⃣ Loop definiciones (por prioridad asc)
    for (const def of defs) {
      const prioridad = Number((def as any).prioridad ?? 2);
      const operariosIds = def.operarios.map((o) => o.id);

      // evitar duplicar si ya fue publicada
      const yaPublicadaEstaDef = await this.prisma.tarea.count({
        where: {
          conjuntoId,
          periodoAnio,
          periodoMes,
          tipo: TipoTarea.PREVENTIVA,
          borrador: false,
          descripcion: def.descripcion,
          ubicacionId: def.ubicacionId,
          elementoId: def.elementoId,
          frecuencia: def.frecuencia,
        },
      });
      if (yaPublicadaEstaDef > 0) continue;

      // días según frecuencia
      const diasBase = pickDaysByFrecuencia(fechasDelMes, def);

      // solo días con horario
      const diasValidos = diasBase.filter((d) =>
        horariosPorDia.has(dateToDiaSemana(d)),
      );

      for (const diaBase of diasValidos) {
        const diaProgramable = findNextValidDay({
          start: diaBase,
          periodoAnio,
          periodoMes,
          prioridad,
          horariosPorDia,
          festivosSet,
        });
          if (!diaProgramable) {
            const diaBaseEsFestivo = festivosSet.has(dayKey(diaBase));
            const diaBaseEsDomingo = dateToDiaSemana(diaBase) === DiaSemana.DOMINGO;
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
                defId: def.id,
                fechaObjetivo: diaBase,
                duracionMinutos: Math.max(1, tamanoBloqueMinutos),
                motivoTipo: "FESTIVO_OMITIDO",
                motivoMensaje: mensaje,
                metadataJson: {
                  motivo: diaBaseEsDomingo ? "DOMINGO" : "FESTIVO",
                },
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

          let diaParte = findNextValidDay({
            start: cursorDia,
            periodoAnio,
            periodoMes,
            prioridad,
            horariosPorDia,
            festivosSet,
          });
          if (!diaParte) break;

          let agendada = false;
          let pendienteConfirmacion:
            | {
                fecha: string;
                prioridadObjetivo: 2 | 3;
                candidatasIds: number[];
              }
            | null = null;
          let diasSinCandidatasP3 = 0;
          let diasConCandidatasP3SinHueco = 0;
          const fechasConCandidatasP3 = new Set<string>();
          let diasConCandidatasP3ParaP2 = 0;
          let diasSinCandidatasP3ParaP2 = 0;
          let intentosConfirmadosP2ConP3Fallidos = 0;

          // Regla: para P1 y P2, buscar hueco/reemplazo solo sobre la
          // fecha objetivo actual (normalmente el siguiente dia habil).
          const finSemanaBusqueda = new Date(diaParte);
          finSemanaBusqueda.setHours(23, 59, 59, 999);

          for (let guardDia = 0; guardDia < 8; guardDia++) {
            if (!diaParte) break;
            if ((prioridad === 1 || prioridad === 2) && +diaParte > +finSemanaBusqueda) break;

            // Nunca crear bloques fuera del periodo solicitado.
            if (
              diaParte.getFullYear() !== periodoAnio ||
              diaParte.getMonth() + 1 !== periodoMes
            ) {
              diaParte = null;
              break;
            }

            const diaParteKey = dayKey(diaParte);
            const esFestivo = festivosSet.has(diaParteKey);
            const disponibilidadOperarios = operariosIds.length
              ? await validarOperariosDisponiblesEnFecha({
                  prisma: this.prisma,
                  fecha: diaParte,
                  operariosIds,
                })
              : { ok: true, noDisponibles: [] as string[] };

            if (esFestivo || !disponibilidadOperarios.ok) {
              if (prioridad === 1 || prioridad === 2) {
                break;
              }
              break;
            }

            const horario = horariosPorDia.get(dateToDiaSemana(diaParte));
            if (!horario) {
              break;
            }

            // ✅ 1) Descanso
            const bloqueosDescanso = buildBloqueosPorDescanso(horario);

            // ✅ 2) Patrón jornada (bloqueos por operario)
            const bloqueosPatron = await buildBloqueosPorPatronJornada({
              prisma: this.prisma,
              fechaDia: diaParte,
              horarioDia: horario,
              operariosIds,
            });

            // ✅ 3) Bloqueos totales
            const bloqueos = [...bloqueosDescanso, ...bloqueosPatron];

            // agenda por operarios => ocupados global merged
            let ocupadosGlobal: Intervalo[] = [];

            if (operariosIds.length) {
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
              for (const opId of Object.keys(agenda)) all.push(...agenda[opId]);
              ocupadosGlobal = mergeIntervalos(all);
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
            });

            if (bloquesFound) {
              // ✅ validar límite semanal (POR OPERARIO)
              let pasaLimite = true;

              for (const opId of operariosIds) {
                // cache límite por operario
                let limiteOp = limitePorOperario.get(opId);
                if (limiteOp == null) {
                  limiteOp = await getLimiteMinSemanaPorOperario({
                    prisma: this.prisma,
                    conjuntoId,
                    operarioId: opId,
                    horariosPorDia: horariosPorDia as any,
                  });
                  limitePorOperario.set(opId, limiteOp);
                }

                const minSemana = await minutosAsignadosEnSemana(
                  this.prisma,
                  conjuntoId,
                  opId,
                  toDateAtMin(diaParte, bloquesFound[0].i),
                  incluirPublicadasEnAgenda,
                );

                if (minSemana + durMinParte > limiteOp) {
                  pasaLimite = false;
                  break;
                }
              }

              if (!pasaLimite) {
                if (prioridad === 1 || prioridad === 2) {
                  diaParte = siguienteDiaHabil({
                    fecha: diaParte,
                    festivosSet,
                    horariosPorDia,
                  });
                  continue;
                }
                break;
              }

              // ✅ crear tareas
              for (const b of bloquesFound) {
                const fechaInicio = toDateAtMin(diaParte, b.i);
                const fechaFin = toDateAtMin(diaParte, b.f);

                await this.prisma.tarea.create({
                  data: {
                    descripcion: def.descripcion,
                    fechaInicio,
                    fechaFin,
                    duracionMinutos: Math.max(1, b.f - b.i),

                    tipo: TipoTarea.PREVENTIVA,
                    prioridad,
                    estado: EstadoTarea.ASIGNADA,
                    frecuencia: def.frecuencia,

                    borrador: true,
                    periodoAnio,
                    periodoMes,

                    grupoPlanId,
                    bloqueIndex: grupoPlanId ? bloqueIndexCursor : null,
                    bloquesTotales: grupoPlanId ? totalBloquesEsperados : null,

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

                    herramientasPlanJson: (def as any).herramientasPlanJson
                      ? ((def as any)
                          .herramientasPlanJson as Prisma.InputJsonValue)
                      : undefined,

                    operarios: operariosIds.length
                      ? { connect: operariosIds.map((id) => ({ id })) }
                      : undefined,
                  },
                });

                creadas++;
                if (grupoPlanId) bloqueIndexCursor++;
              }

              agendada = true;
              break;
            }

            // ❌ No hubo hueco
            if (prioridad === 1 || prioridad === 2) {
              const payload: any = {
                descripcion: def.descripcion,
                tipo: TipoTarea.PREVENTIVA,
                frecuencia: def.frecuencia ?? null,

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
              };

              const fechaIntento = dayKey(diaParte);

              // P1: auto reemplaza P3; P2 solo por confirmacion del usuario.
              if (prioridad === 1) {
                const repAutoP3 = await intentarReemplazoPorPrioridadBaja({
                  prisma: this.prisma,
                  conjuntoId,
                  fechaDia: diaParte,
                  startMin: horario.startMin,
                  endMin: horario.endMin,
                  bloqueos,
                  durMin: durMinParte,
                  payload,
                  prioridadesCandidatas: [3],
                  incluirBorradorEnAgenda: true,
                  incluirPublicadasEnAgenda,
                  onEvent: (ev) => {
                    if (ev.tipo === "REEMPLAZO") {
                      if (ev.reprogramadasIds.length) {
                        novedades.push({
                          tipo: "REEMPLAZO_PRIORIDAD",
                          defId: def.id,
                          descripcion: def.descripcion,
                          prioridad,
                          fecha: dayKey(diaParte!),
                          nuevaTareaIds: ev.nuevaTareaIds,
                          reprogramadasIds: ev.reprogramadasIds,
                        });
                      }
                    } else if (ev.tipo === "SIN_CANDIDATAS") {
                      diasSinCandidatasP3++;
                    } else if (ev.tipo === "SIN_HUECO") {
                      diasConCandidatasP3SinHueco++;
                      fechasConCandidatasP3.add(fechaIntento);
                    }
                  },
                });

                if (repAutoP3.ok) {
                  creadas += repAutoP3.nuevaTareaIds.length;
                  if (grupoPlanId)
                    bloqueIndexCursor += repAutoP3.nuevaTareaIds.length;

                  agendada = true;
                  break;
                }

                const candidatasP2 = await listarCandidatasPorPrioridadDia(
                  diaParte,
                  [2],
                );
                const confirmP2 = obtenerConfirmacion({
                  defId: def.id,
                  fecha: fechaIntento,
                  prioridadSolicitante: 1,
                  prioridadObjetivo: 2,
                });

                if (confirmP2?.aceptar === true && candidatasP2.length) {
                  const candidatasPreferidas = confirmP2.candidataId
                    ? [confirmP2.candidataId]
                    : candidatasP2;

                  const repConfirmadoP2 = await intentarReemplazoPorPrioridadBaja(
                    {
                      prisma: this.prisma,
                      conjuntoId,
                      fechaDia: diaParte,
                      startMin: horario.startMin,
                      endMin: horario.endMin,
                      bloqueos,
                      durMin: durMinParte,
                      payload,
                      prioridadesCandidatas: [2],
                      candidatasIdsPreferidas: candidatasPreferidas,
                      marcarReemplazadasComoNoCompletadas:
                        confirmP2.reprogramarReemplazada === false,
                      incluirBorradorEnAgenda: true,
                      incluirPublicadasEnAgenda,
                      onEvent: (ev) => {
                        if (
                          ev.tipo === "REEMPLAZO" &&
                          ev.reprogramadasIds.length
                        ) {
                          novedades.push({
                            tipo: "REEMPLAZO_PRIORIDAD",
                            defId: def.id,
                            descripcion: def.descripcion,
                            prioridad,
                            fecha: dayKey(diaParte!),
                            nuevaTareaIds: ev.nuevaTareaIds,
                            reprogramadasIds: ev.reprogramadasIds,
                            mensaje:
                              "Reemplazo confirmado por usuario sobre prioridad 2.",
                          });
                        }
                      },
                    },
                  );

                  if (repConfirmadoP2.ok) {
                    creadas += repConfirmadoP2.nuevaTareaIds.length;
                    if (grupoPlanId)
                      bloqueIndexCursor += repConfirmadoP2.nuevaTareaIds.length;
                    agendada = true;
                    break;
                  }
                } else if (confirmP2 == null && candidatasP2.length) {
                  pendienteConfirmacion ??= {
                    fecha: fechaIntento,
                    prioridadObjetivo: 2,
                    candidatasIds: candidatasP2,
                  };
                }

                break;
              }

              // P2: no reemplaza automatico; sugiere reemplazo de P3 con confirmacion.
              const candidatasP3 = await listarCandidatasPorPrioridadDia(
                diaParte,
                [3],
              );
              if (candidatasP3.length) diasConCandidatasP3ParaP2++;
              else diasSinCandidatasP3ParaP2++;

              const confirmP3 = obtenerConfirmacion({
                defId: def.id,
                fecha: fechaIntento,
                prioridadSolicitante: 2,
                prioridadObjetivo: 3,
              });

              if (confirmP3?.aceptar === true && candidatasP3.length) {
                const candidatasPreferidas = confirmP3.candidataId
                  ? [confirmP3.candidataId]
                  : candidatasP3;

                const repConfirmadoP3 = await intentarReemplazoPorPrioridadBaja(
                  {
                    prisma: this.prisma,
                    conjuntoId,
                    fechaDia: diaParte,
                    startMin: horario.startMin,
                    endMin: horario.endMin,
                    bloqueos,
                    durMin: durMinParte,
                    payload,
                    prioridadesCandidatas: [3],
                      candidatasIdsPreferidas: candidatasPreferidas,
                      marcarReemplazadasComoNoCompletadas:
                        confirmP3.reprogramarReemplazada === false,
                      incluirBorradorEnAgenda: true,
                    incluirPublicadasEnAgenda,
                    onEvent: (ev) => {
                      if (
                        ev.tipo === "REEMPLAZO" &&
                        ev.reprogramadasIds.length
                      ) {
                        novedades.push({
                          tipo: "REEMPLAZO_PRIORIDAD",
                          defId: def.id,
                          descripcion: def.descripcion,
                          prioridad,
                          fecha: dayKey(diaParte!),
                          nuevaTareaIds: ev.nuevaTareaIds,
                          reprogramadasIds: ev.reprogramadasIds,
                          mensaje:
                            "Reemplazo confirmado por usuario sobre prioridad 3.",
                        });
                      }
                    },
                  },
                );

                if (repConfirmadoP3.ok) {
                  creadas += repConfirmadoP3.nuevaTareaIds.length;
                  if (grupoPlanId)
                    bloqueIndexCursor += repConfirmadoP3.nuevaTareaIds.length;
                  agendada = true;
                  break;
                }
                intentosConfirmadosP2ConP3Fallidos++;
              } else if (confirmP3 == null && candidatasP3.length) {
                pendienteConfirmacion ??= {
                  fecha: fechaIntento,
                  prioridadObjetivo: 3,
                  candidatasIds: candidatasP3,
                };
              }

              break;
            }

            // prioridad 3: si no cabe, se omite
            break;
          }

          if (!agendada && (prioridad === 1 || prioridad === 2)) {
            if (pendienteConfirmacion != null) {
              const p3Contexto =
                prioridad === 1 && diasConCandidatasP3SinHueco > 0
                  ? ` Se evaluaron candidatas P3 en ${diasConCandidatasP3SinHueco} dia(s), pero no liberaron hueco.`
                  : "";

              const objetivo = pendienteConfirmacion.prioridadObjetivo;
              const msgObjetivo =
                objetivo === 2
                  ? "Hay opcion de reemplazo con prioridad 2 y requiere confirmacion."
                  : "Hay opcion de reemplazo con prioridad 3 y requiere confirmacion.";

              novedades.push({
                tipo: "REQUIERE_CONFIRMACION_REEMPLAZO",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: pendienteConfirmacion.fecha,
                prioridadObjetivo: objetivo,
                candidatasIds: pendienteConfirmacion.candidatasIds,
                mensaje: `No se encontro hueco ni reemplazo automatico en la fecha objetivo.${p3Contexto} ${msgObjetivo}`,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                defId: def.id,
                fechaObjetivo: diaParte ?? cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "REQUIERE_CONFIRMACION_REEMPLAZO",
                motivoMensaje: `No se encontro hueco ni reemplazo automatico en la fecha objetivo.${p3Contexto} ${msgObjetivo}`,
                metadataJson: {
                  fecha: pendienteConfirmacion.fecha,
                  prioridadObjetivo: objetivo,
                  candidatasIds: pendienteConfirmacion.candidatasIds,
                },
              });
            } else if (prioridad === 1 && diasConCandidatasP3SinHueco > 0) {
              const fechas = Array.from(fechasConCandidatasP3).sort();
              const fechasTxt =
                fechas.length > 0
                  ? ` Fechas evaluadas: ${fechas.slice(0, 4).join(", ")}${fechas.length > 4 ? ` (+${fechas.length - 4} mas)` : ""}.`
                  : "";
              novedades.push({
                tipo: "SIN_HUECO",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: dayKey(diaParte ?? cursorDia),
                mensaje: `Se encontraron candidatas P3 en la fecha objetivo, pero ninguna libero hueco para ubicar la tarea.${fechasTxt}`,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                defId: def.id,
                fechaObjetivo: diaParte ?? cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "SIN_HUECO",
                motivoMensaje: `Se encontraron candidatas P3 en la fecha objetivo, pero ninguna libero hueco para ubicar la tarea.${fechasTxt}`,
                metadataJson: { fechasEvaluadas: fechas },
              });
            } else if (prioridad === 1) {
              novedades.push({
                tipo: "SIN_CANDIDATAS",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: dayKey(diaParte ?? cursorDia),
                mensaje: `No se encontraron tareas candidatas P3 para reemplazo en la fecha objetivo.`,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                defId: def.id,
                fechaObjetivo: diaParte ?? cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "SIN_CANDIDATAS",
                motivoMensaje: "No se encontraron tareas candidatas P3 para reemplazo en la fecha objetivo.",
              });
            } else if (
              diasConCandidatasP3ParaP2 > 0 ||
              intentosConfirmadosP2ConP3Fallidos > 0
            ) {
              novedades.push({
                tipo: "SIN_HUECO",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: dayKey(diaParte ?? cursorDia),
                mensaje: `Se encontraron candidatas P3 para reemplazo en la fecha objetivo, pero no se logro agendar la tarea.`,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                defId: def.id,
                fechaObjetivo: diaParte ?? cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "SIN_HUECO",
                motivoMensaje: "Se encontraron candidatas P3 para reemplazo en la fecha objetivo, pero no se logro agendar la tarea.",
              });
            } else {
              novedades.push({
                tipo: "SIN_CANDIDATAS",
                defId: def.id,
                descripcion: def.descripcion,
                prioridad,
                fecha: dayKey(diaParte ?? cursorDia),
                mensaje: `No se encontraron candidatas P3 para reemplazo de esta tarea de prioridad 2 en la fecha objetivo.`,
              });
              await this.crearExcluidaDesdeDefinicion({
                conjuntoId,
                periodoAnio,
                periodoMes,
                defId: def.id,
                fechaObjetivo: diaParte ?? cursorDia,
                duracionMinutos: durMinParte,
                motivoTipo: "SIN_CANDIDATAS",
                motivoMensaje: "No se encontraron candidatas P3 para reemplazo de esta tarea de prioridad 2 en la fecha objetivo.",
              });
            }
          }

          // mover cursor al siguiente día (para la siguiente parte)
          cursorDia = new Date(diaParte ?? cursorDia);
          cursorDia.setDate(cursorDia.getDate() + 1);

          if (!agendada) break;
        }
      }
    }

    return { creadas, novedades };
  }

  async editarTareaBorrador(payload: unknown) {
    const dto = EditarBorradorDTO.parse(payload);

    const t = await this.prisma.tarea.findUnique({
      where: { id: dto.tareaId },
      select: { id: true, borrador: true, conjuntoId: true },
    });
    if (!t || !t.borrador || t.conjuntoId !== dto.conjuntoId) {
      throw new Error(
        "Tarea no existe, no es borrador o no pertenece a este conjunto.",
      );
    }
    if (dto.fechaInicio && dto.fechaFin && dto.fechaFin < dto.fechaInicio) {
      throw new Error("fechaFin debe ser >= fechaInicio");
    }

    return this.prisma.tarea.update({
      where: { id: dto.tareaId },
      data: {
        fechaInicio: dto.fechaInicio ?? undefined,
        fechaFin: dto.fechaFin ?? undefined,
        duracionMinutos: dto.duracionMinutos ?? undefined,
        operarios:
          dto.operariosIds !== undefined
            ? { set: dto.operariosIds.map((id) => ({ id: id.toString() })) }
            : undefined,
      },
      include: { operarios: { select: { id: true } } },
    });
  }

  async crearBloqueBorrador(conjuntoId: string, payload: unknown) {
    const dto = CrearBloqueBorradorDTO.parse(payload);
    if (dto.fechaFin < dto.fechaInicio)
      throw new Error("fechaFin >= fechaInicio");

      const inicioEsFestivo = await isFestivoDate({
        prisma: this.prisma,
        fecha: dto.fechaInicio,
        pais: "CO",
      });
      if (inicioEsFestivo) {
        throw new Error("No se permite programar tareas preventivas en festivos.");
      }

      const disponibilidad = await validarOperariosDisponiblesEnFecha({
        prisma: this.prisma,
        fecha: dto.fechaInicio,
        operariosIds: (dto.operariosIds ?? []).map((id) => id.toString()),
      });
      if (!disponibilidad.ok) {
        throw new Error(
          `Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`,
        );
      }

    if (dto.operariosIds?.length) {
      for (const opId of dto.operariosIds) {
        const choque = await this.prisma.tarea.findFirst({
          where: {
            conjuntoId,
            borrador: true,
            tipo: TipoTarea.PREVENTIVA,
            fechaInicio: { lt: dto.fechaFin },
            fechaFin: { gt: dto.fechaInicio },
            operarios: { some: { id: opId.toString() } },
          },
          select: { id: true },
        });

        if (choque) {
          const nombre = await getOperarioNombre(this.prisma, opId);
          throw new Error(`Solape de agenda con ${nombre}`);
        }
      }
    }

    const anio = dto.fechaInicio.getFullYear();
    const mes = dto.fechaInicio.getMonth() + 1;

    return this.prisma.tarea.create({
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
  }

  async editarBloqueBorrador(
    conjuntoId: string,
    tareaId: number,
    payload: unknown,
  ) {
    const dto = EditarBloqueBorradorDTO.parse(payload);

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { id: true, conjuntoId: true, borrador: true, tipo: true },
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
      const actuales = await this.prisma.tarea.findUnique({
        where: { id: tareaId },
        select: { operarios: { select: { id: true } } },
      });
      operariosIdsFinal = actuales?.operarios.map((o) => o.id) ?? [];
    }

    const fechaInicio = dto.fechaInicio ?? undefined;
    const fechaFin = dto.fechaFin ?? undefined;

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
            `Los operarios ${disponibilidad.noDisponibles.join(", ")} no tienen disponibilidad para ese dia.`,
          );
        }
      }
    }

    if (fechaInicio && fechaFin && operariosIdsFinal.length) {
      for (const opId of operariosIdsFinal) {
        const haySolape = await existeSolapeParaOperario(this.prisma, {
          conjuntoId,
          operarioId: opId,
          fechaInicio,
          fechaFin,
          soloBorrador: true,
          excluirTareaId: tareaId,
        });

        if (haySolape) {
          const nombre = await getOperarioNombre(this.prisma, opId);
          throw new Error(`Solape de agenda con operario ${nombre}`);
        }
      }
    }

    return this.prisma.tarea.update({
      where: { id: tareaId },
      data: {
        descripcion: dto.descripcion ?? undefined,
        fechaInicio,
        fechaFin,
        duracionMinutos:
          dto.duracionMinutos ??
          (fechaInicio && fechaFin
            ? Math.max(1, Math.round((+fechaFin - +fechaInicio) / 60000))
            : undefined),
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
  }

  async reasignarOperarioTareaBorrador(payload: unknown) {
    const dto = ReasignarOperarioBorradorDTO.parse(payload);
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

    const tareaActualizada = await this.editarBloqueBorrador(
      dto.conjuntoId,
      dto.tareaId,
      {
        fechaInicio: tarea.fechaInicio,
        fechaFin: tarea.fechaFin,
        operariosIds: [dto.nuevoOperarioId],
      },
    );

    let definicionActualizada = false;
    let definicionId: number | null = null;
    let warning: string | null = null;

    if (dto.aplicarADefinicion) {
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
      definicionActualizada,
      definicionId,
      warning,
    };
  }

  async reasignarOperarioExcluidaBorrador(payload: unknown) {
    const dto = ReasignarOperarioExcluidaDTO.parse(payload);
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
    const excluidaActualizada = await this.prisma.preventivaExcluidaBorrador.update({
      where: { id: dto.excluidaId },
      data: {
        operariosIds: [nuevoOperarioId],
        operariosNombres: nombreOperario ? [nombreOperario] : [],
      },
    });

    let definicionActualizada = false;
    let warning: string | null = null;

    if (dto.aplicarADefinicion) {
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
      excluidaId: excluida.id,
      detalle: `Se reasignó el operario de la tarea excluida al operario ${nombreOperario || nuevoOperarioId}.`,
      metadataJson: {
        nuevoOperarioId,
        nuevoOperarioNombre: nombreOperario,
        aplicarADefinicion: dto.aplicarADefinicion,
      },
    });

    return {
      ok: true,
      excluida: excluidaActualizada,
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
    if (total !== excluida.duracionMinutos) {
      throw new Error("La suma de horas de los bloques debe coincidir con la duración total de la tarea excluida.");
    }

    const division: DivisionManualExcluida = {
      activa: true,
      actualizadaEn: new Date().toISOString(),
      bloques: dto.bloques.map((bloque, index) => ({
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
          metadataJson: {
            bloqueId: bloque.id,
            orden: bloque.orden,
            fechaInicio: fechaInicio.toISOString(),
            fechaFin: fechaFin.toISOString(),
            completaExcluida: todosAgendados,
          },
        },
      });

      return creada;
    });

    return { ok: true, tarea };
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
  }) {
    const { conjuntoId, fechaInicioUso, fechaFinUso, excluirTareaId } = params;

    if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
      return { ok: false, reason: "FECHA_INICIO_INVALIDA" as const };
    }
    if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
      return { ok: false, reason: "FECHA_FIN_INVALIDA" as const };
    }
    if (+fechaFinUso < +fechaInicioUso) {
      return { ok: false, reason: "RANGO_INVERTIDO" as const };
    }

    const diasEntregaRecogida = new Set([1, 3, 6]); // Lunes, Miércoles, Sábado

    const { iniReserva, finReserva, entregaDia, recogidaDia } =
      this.calcularRangoReserva({
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
            fechaInicio: true,
            fechaFin: true,
            borrador: true,
          },
        },
      },
    });

    const getMaqIds = (json: any): number[] => {
      if (!Array.isArray(json)) return [];
      return json
        .map((x) => Number(x?.maquinariaId))
        .filter((n) => Number.isFinite(n) && n > 0);
    };

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
          getMaqIds(t.maquinariaPlanJson).filter((id) => idsInteresSet.has(id)),
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
      descripcion: string;
      fuente: "BORRADOR_PREVENTIVA";
    }> = [];

    for (const g of gruposBorrador.values()) {
      const rangoBorrador = this.calcularRangoReserva({
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

      const desc = (g.descripcion ?? "Preventiva en borrador").trim();
      for (const maquinariaId of g.maqIds) {
        ocupadasBorrador.push({
          maquinariaId,
          ini: rangoBorrador.iniReserva,
          fin: rangoBorrador.finReserva,
          tareaId: g.tareaIdRepresentante,
          conjuntoId: g.conjuntoId ?? null,
          descripcion: `[BORRADOR] ${desc}`,
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
        descripcion: o.tarea?.borrador
          ? `[BORRADOR] ${(o.tarea?.descripcion ?? "Tarea en borrador").trim()}`
          : o.tarea?.descripcion ?? null,
        fuente: "RESERVA_PUBLICADA" as const,
      })),
      ...ocupadasBorrador,
    ];

    const ocupadasSet = new Set(ocupadasDetalle.map((o) => o.maquinariaId));

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

    return {
      ok: true,
      rango: { entregaDia, recogidaDia, iniReserva, finReserva },
      propiasDisponibles,
      empresaDisponibles,
      ocupadas: ocupadasDetalle,
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
      select: { id: true },
    });
    if (!tarea) {
      throw new Error("Bloque no encontrado o no es borrador preventivo.");
    }

    await this.crearExcluidaDesdeTarea({
      tareaId,
      motivoTipo: "MANUAL_ELIMINADA",
      motivoMensaje: "La tarea fue retirada manualmente del borrador.",
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
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        supervisor: { include: { usuario: true } },
      },
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

    const getMaqIds = (json: any): number[] => {
      if (!Array.isArray(json)) return [];
      return json
        .map((x) => Number(x?.maquinariaId))
        .filter((n) => Number.isFinite(n) && n > 0);
    };

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
      const maqIds = getMaqIds(t.maquinariaPlanJson);
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
        this.calcularRangoReserva({
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
          conflictosInternos.push({
            tareaId: a.tareaIdRepresentante,
            tareaDescripcion: a.descripcion,
            maquinariaId,
            rangoSolicitado: {
              ini: a.iniReserva.toISOString(),
              fin: a.finReserva.toISOString(),
              entrega: sameDayKey(a.entregaDia),
              recogida: sameDayKey(a.recogidaDia),
            },
            ocupadoPor: {
              usoId: 0,
              tareaId: b.tareaIdRepresentante,
              conjuntoId,
              descripcion: `[BORRADOR] ${(b.descripcion ?? "Preventiva en borrador").trim()}`,
              ini: b.iniReserva.toISOString(),
              fin: b.finReserva.toISOString(),
            },
          });
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

          conflictos.push({
            tareaId: p.tareaIdRepresentante,
            tareaDescripcion: p.descripcion,
            maquinariaId,
            rangoSolicitado: {
              ini: p.iniReserva.toISOString(),
              fin: p.finReserva.toISOString(),
              entrega: sameDayKey(p.entregaDia),
              recogida: sameDayKey(p.recogidaDia),
            },
            ocupadoPor: {
              usoId: u.id,
              tareaId: u.tareaId,
              conjuntoId: u.tarea?.conjuntoId ?? null,
              descripcion: u.tarea?.borrador
                ? `[BORRADOR] ${(u.tarea?.descripcion ?? "Tarea en borrador").trim()}`
                : u.tarea?.descripcion ?? null,
              ini: u.fechaInicio.toISOString(),
              fin: (u.fechaFin ?? OPEN_END_FAR_FUTURE).toISOString(),
            },
          });
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

      const first = conflictos[0];
      const maquinaNombre = nombrePorId.get(first.maquinariaId);

      throw buildMaquinariaNoDisponibleError({
        maquinariaId: first.maquinariaId,
        maquinaNombre,
        conflictos,
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

  private buscarDiaPermitidoAnterior(
    fecha: Date,
    diasPermitidos: Set<number>,
    festivosSet?: Set<string>,
  ) {
    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);

    const key = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    let d = atStartOfDay(fecha);
    d.setDate(d.getDate() - 1);

    for (let guard = 0; guard < 62; guard++) {
      const k = key(d);
      const esFestivo = festivosSet?.has(k) ?? false;

      if (diasPermitidos.has(d.getDay()) && !esFestivo) return new Date(d);
      d.setDate(d.getDate() - 1);
    }

    return atStartOfDay(fecha);
  }

  private buscarDiaPermitidoPosterior(
    fecha: Date,
    diasPermitidos: Set<number>,
    festivosSet?: Set<string>,
  ) {
    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);

    const key = (d: Date) =>
      `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;

    let d = atStartOfDay(fecha);
    d.setDate(d.getDate() + 1);

    for (let guard = 0; guard < 62; guard++) {
      const k = key(d);
      const esFestivo = festivosSet?.has(k) ?? false;

      if (diasPermitidos.has(d.getDay()) && !esFestivo) return new Date(d);
      d.setDate(d.getDate() + 1);
    }

    return atStartOfDay(fecha);
  }

  private calcularRangoReserva(params: {
    fechaInicioUso: Date;
    fechaFinUso: Date;
    diasEntregaRecogida: Set<number>;
    festivosSet?: Set<string>;
  }) {
    const { fechaInicioUso, fechaFinUso, diasEntregaRecogida, festivosSet } =
      params;

    if (!(fechaInicioUso instanceof Date) || isNaN(+fechaInicioUso)) {
      throw new Error("fechaInicioUso inválida");
    }
    if (!(fechaFinUso instanceof Date) || isNaN(+fechaFinUso)) {
      throw new Error("fechaFinUso inválida");
    }

    const iniUso =
      +fechaInicioUso <= +fechaFinUso ? fechaInicioUso : fechaFinUso;
    const finUso =
      +fechaInicioUso <= +fechaFinUso ? fechaFinUso : fechaInicioUso;

    if (!diasEntregaRecogida || diasEntregaRecogida.size === 0) {
      throw new Error("diasEntregaRecogida vacío");
    }

    const atStartOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 0, 0, 0, 0);

    const atEndOfDay = (d: Date) =>
      new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59, 999);

    const usoInicioDia = atStartOfDay(iniUso);
    const usoFinDia = atStartOfDay(finUso);

    const entregaDia = this.buscarDiaPermitidoAnterior(
      usoInicioDia,
      diasEntregaRecogida,
      festivosSet,
    );

    const recogidaDia = this.buscarDiaPermitidoPosterior(
      usoFinDia,
      diasEntregaRecogida,
      festivosSet,
    );

    const iniReserva = atStartOfDay(entregaDia);
    const finReserva = atEndOfDay(recogidaDia);

    if (+finReserva < +iniReserva) {
      throw new Error("Rango de reserva inválido (fin < inicio)");
    }

    return { entregaDia, recogidaDia, iniReserva, finReserva };
  }
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

function pickDaysByFrecuencia(days: Date[], def: any): Date[] {
  switch (def.frecuencia) {
    case Frecuencia.DIARIA:
      return days;

    case Frecuencia.SEMANAL: {
      const dia = def.diaSemanaProgramado ?? DiaSemana.LUNES;
      const target = diaSemanaToJsDay(dia);
      return days.filter((d) => d.getDay() === target);
    }

    case Frecuencia.MENSUAL: {
      const dd = def.diaMesProgramado ?? 1;
      return days.filter((d) => d.getDate() === dd);
    }

    default:
      return days;
  }
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

  const a = allowed[0];
  const out: Bloqueo[] = [];

  if (horario.startMin < a.i)
    out.push({ startMin: horario.startMin, endMin: a.i, motivo });
  if (a.f < horario.endMin)
    out.push({ startMin: a.f, endMin: horario.endMin, motivo });

  return out;
}

/**
 * Bloqueos por patrón (si uno NO puede, se bloquea).
 */
export async function buildBloqueosPorPatronJornada(params: {
  prisma: PrismaClient;
  fechaDia: Date;
  horarioDia: HorarioDia;
  operariosIds: string[];
}): Promise<Bloqueo[]> {
  const { prisma, fechaDia, horarioDia, operariosIds } = params;
  if (!operariosIds.length) return [];

  const dia = diaSemanaFromDate(fechaDia);

  const ops = await prisma.operario.findMany({
    where: { id: { in: operariosIds.map(String) } },
    select: {
      id: true,
      usuario: {
        select: {
          jornadaLaboral: true,
          patronJornada: true,
        },
      },
    },
  });
  const disponibilidadByOp = await obtenerDisponibilidadActivaOperarios({
    prisma,
    operariosIds,
    fecha: fechaDia,
  });

  const bloqueos: Bloqueo[] = [];

  for (const op of ops) {
    const jl = op.usuario?.jornadaLaboral as Jornada | null;
    const pj = op.usuario?.patronJornada as string | null;

    if (jl === "COMPLETA") continue;

    const allowed = allowedIntervalsForUserWithAvailability({
      dia,
      horario: horarioDia,
      jornadaLaboral: jl,
      patronJornada: pj,
      disponibilidad: disponibilidadByOp.get(op.id)
        ? {
            trabajaDomingo: disponibilidadByOp.get(op.id)!.trabajaDomingo,
            diaDescanso: disponibilidadByOp.get(op.id)!.diaDescanso,
          }
        : null,
    });

    bloqueos.push(
      ...bloqueosFromAllowed({
        horario: horarioDia,
        allowed,
        motivo: `PATRON_${op.id}`,
      }),
    );
  }

  return bloqueos;
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
