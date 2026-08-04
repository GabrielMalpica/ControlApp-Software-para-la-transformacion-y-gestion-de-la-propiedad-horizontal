// src/services/CronogramaService.ts
import { EstadoTarea, Prisma, TipoTarea, type PrismaClient } from "@prisma/client";
import { z } from "zod";
import {
  buildAgendaPorOperarioDia,
  buscarHuecoDiaConSplitEarliest,
  dateToDiaSemana,
  freeFromOccupied,
  isFestivoDate,
  mergeIntervalos,
  toMin,
  toMinOfDay,
  type Bloqueo,
  type Intervalo,
} from "../utils/schedulerUtils";
import {
  construirRutaElemento,
  elementoParentChainInclude,
} from "../utils/elementoHierarchy";
import {
  validarLimiteSemanalOperarios,
  validarOperariosDisponiblesEnFecha,
} from "../utils/operarioAvailability";
import {
  AccionAuditoria,
  EntidadAuditoria,
  ModuloAuditoria,
  type ActorAuditoria,
} from "../model/Auditoria";
import { AuditoriaService } from "./AuditoriaService";
import { GerenteService } from "./GerenteServices";

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

const CronoMesDTO = z.object({
  anio: z.number().int().min(2000).max(2100),
  mes: z.number().int().min(1).max(12),
  borrador: z.boolean().optional(), // undefined = todos, true = solo borrador, false = solo operativo
});

const ExcluidasStandbyDTO = z.object({
  anio: z.number().int().min(2000).max(2100),
  mes: z.number().int().min(1).max(12),
  fecha: z.coerce.date().optional(),
});

const ProgramarExcluidaComoCorrectivaDTO = z.object({
  excluidaId: z.number().int().positive(),
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date().optional(),
  // `reemplazarTareaId` se conserva por compatibilidad; `reemplazarTareaIds` permite
  // desplazar varias tareas hasta liberar el espacio necesario.
  reemplazarTareaId: z.number().int().positive().optional(),
  reemplazarTareaIds: z.array(z.number().int().positive()).min(1).optional(),
  accionReemplazadas: z.enum(["REPROGRAMAR", "CANCELAR"]).optional(),
  // El motor de reemplazo exige entre 3 y 500 caracteres: validarlo aqui evita
  // que la operacion falle en silencio mas abajo.
  motivoReemplazo: z.string().trim().min(3).max(500).optional(),
});

const OpcionesReemplazoExcluidaDTO = z.object({
  excluidaId: z.coerce.number().int().positive(),
  fecha: z.coerce.date(),
});

const ReasignarOperarioExcluidaPublicadaDTO = z.object({
  excluidaId: z.coerce.number().int().positive(),
  nuevoOperarioId: z.coerce.string().min(1),
  motivo: z.string().trim().max(500).optional(),
});

const InformeExcluidasDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
});

const EliminarCronogramaPublicadoDTO = z.object({
  anio: z.coerce.number().int().min(2000).max(2100),
  mes: z.coerce.number().int().min(1).max(12),
});

const SugerirDTO = z.object({
  fechaInicio: z.coerce.date(),
  fechaFin: z.coerce.date(),
  max: z.number().int().min(1).max(20).optional().default(5),
  requiereFuncion: z.string().optional(),
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

const ESTADOS_NO_CRONOGRAMA = ["PENDIENTE_REPROGRAMACION"] as any;

/** Acepta el campo singular antiguo y el plural nuevo, sin duplicar ids. */
function normalizarIdsReemplazo(dto: {
  reemplazarTareaId?: number;
  reemplazarTareaIds?: number[];
}): number[] {
  const ids = [
    ...(dto.reemplazarTareaIds ?? []),
    ...(dto.reemplazarTareaId != null ? [dto.reemplazarTareaId] : []),
  ];
  return Array.from(new Set(ids));
}

function metadataComoObjeto(value: unknown): Record<string, any> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, any>;
  }
  return {};
}

type HorarioDiaConjunto = {
  startMin: number;
  endMin: number;
  descansoStartMin: number | null;
  descansoEndMin: number | null;
};

/** El descanso solo bloquea si queda estrictamente dentro de la jornada. */
function bloqueosPorDescanso(horario: HorarioDiaConjunto): Bloqueo[] {
  const inicio = horario.descansoStartMin;
  const fin = horario.descansoEndMin;
  if (inicio == null || fin == null) return [];
  if (!(horario.startMin < inicio && inicio < fin && fin < horario.endMin)) return [];
  return [{ startMin: inicio, endMin: fin, reason: "DESCANSO" }];
}

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

const WEEKDAY_NAMES_ES = [
  "domingo",
  "lunes",
  "martes",
  "miercoles",
  "jueves",
  "viernes",
  "sabado",
] as const;

function dateKeyLocal(d: Date) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

/**
 * Borra las tareas excluidas de periodos anteriores al indicado.
 * Sin `conjuntoId` aplica a todos los conjuntos: es lo que usa el cron mensual.
 */
export async function purgarExcluidasDeMesesAnteriores(
  prisma: PrismaClient,
  params: { conjuntoId?: string; anio: number; mes: number },
): Promise<number> {
  const { conjuntoId, anio, mes } = params;

  const { count } = await prisma.preventivaExcluidaBorrador.deleteMany({
    where: {
      ...(conjuntoId ? { conjuntoId } : {}),
      OR: [
        { periodoAnio: { lt: anio } },
        { periodoAnio: anio, periodoMes: { lt: mes } },
      ],
    },
  });

  return count;
}

export class CronogramaService {
  private auditoria: AuditoriaService;

  constructor(
    private prisma: PrismaClient,
    private conjuntoId: string,
    private actor?: ActorAuditoria,
  ) {
    this.auditoria = new AuditoriaService(prisma);
  }

  private async limpiarExcluidasDeMesesAnteriores(anio: number, mes: number) {
    await purgarExcluidasDeMesesAnteriores(this.prisma, {
      conjuntoId: this.conjuntoId,
      anio,
      mes,
    });
  }

  private async existeCronogramaPreventivoPublicado(anio: number, mes: number) {
    const total = await this.prisma.tarea.count({
      where: {
        conjuntoId: this.conjuntoId,
        periodoAnio: anio,
        periodoMes: mes,
        borrador: false,
        tipo: TipoTarea.PREVENTIVA,
      },
    });
    return total > 0;
  }

  private async eliminarTareaPublicada(id: number) {
    await this.prisma.$transaction(async (tx) => {
      await tx.maquinariaConjunto.updateMany({
        where: { tareaId: id },
        data: { tareaId: null },
      });

      await tx.usoMaquinaria.deleteMany({ where: { tareaId: id } });
      await tx.usoHerramienta.deleteMany({ where: { tareaId: id } });
      await tx.consumoInsumo.deleteMany({ where: { tareaId: id } });

      await tx.tarea.update({
        where: { id },
        data: { operarios: { set: [] } },
      });

      await tx.tarea.delete({ where: { id } });
    });
  }

  /* ==================== Consultas básicas ==================== */

  async cronogramaMensual(payload: unknown) {
    const { anio, mes, borrador } = CronoMesDTO.parse(payload);

    // Rango del mes
    const inicioMes = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
    const finMes = new Date(anio, mes, 0, 23, 59, 59, 999); // último día del mes

    const where: any = {
      conjuntoId: this.conjuntoId,
      estado: { notIn: ESTADOS_NO_CRONOGRAMA },
      fechaFin: { gte: inicioMes },
      fechaInicio: { lte: finMes },
    };

    if (borrador !== undefined) {
      where.borrador = borrador;
    }

    return this.prisma.tarea.findMany({
      where,
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async informeMensualActividad(payload: unknown) {
    const { anio, mes, borrador } = CronoMesDTO.parse(payload);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: borrador ?? false,
        tipo: "PREVENTIVA",
        periodoAnio: anio,
        periodoMes: mes,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
      },
      select: {
        descripcion: true,
        duracionMinutos: true,
        fechaInicio: true,
      },
      orderBy: [{ descripcion: "asc" }, { fechaInicio: "asc" }],
    });

    const firstDay = new Date(anio, mes - 1, 1);
    const offset = firstDay.getDay() === 0 ? 6 : firstDay.getDay() - 1;

    const rows = new Map<string, {
      actividad: string;
      horasMes: number;
      semana1: number;
      semana2: number;
      semana3: number;
      semana4: number;
      semana5: number;
    }>();

    for (const tarea of tareas) {
      const actividad = tarea.descripcion.trim();
      const horas = Number((tarea.duracionMinutos / 60).toFixed(2));
      const semana = Math.min(
        5,
        Math.floor((tarea.fechaInicio.getDate() + offset - 1) / 7) + 1,
      );

      const row = rows.get(actividad) ?? {
        actividad,
        horasMes: 0,
        semana1: 0,
        semana2: 0,
        semana3: 0,
        semana4: 0,
        semana5: 0,
      };

      row.horasMes = Number((row.horasMes + horas).toFixed(2));
      const key = `semana${semana}` as const;
      row[key] = Number((row[key] + horas).toFixed(2));
      rows.set(actividad, row);
    }

    return Array.from(rows.values()).sort((a, b) =>
      a.actividad.localeCompare(b.actividad),
    );
  }

  async listarExcluidasStandby(payload: unknown) {
    const dto = ExcluidasStandbyDTO.parse(payload);
    await this.limpiarExcluidasDeMesesAnteriores(dto.anio, dto.mes);
    const hayPublicado = await this.existeCronogramaPreventivoPublicado(dto.anio, dto.mes);
    if (!hayPublicado) {
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
        conjuntoId: this.conjuntoId,
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

  async programarExcluidaComoCorrectiva(payload: unknown) {
    const dto = ProgramarExcluidaComoCorrectivaDTO.parse(payload);
    const excluida = await this.cargarExcluidaPendiente(dto.excluidaId);

    const idsAReemplazar = normalizarIdsReemplazo(dto);
    const fechaFin =
      dto.fechaFin ?? new Date(dto.fechaInicio.getTime() + excluida.duracionMinutos * 60000);

    // Snapshot previo: una vez ejecutado el reemplazo las tareas quedan canceladas o
    // reprogramadas, y el informe necesita saber que habia antes.
    const tareasDesplazadas = idsAReemplazar.length
      ? await this.prisma.tarea.findMany({
          where: { id: { in: idsAReemplazar }, conjuntoId: this.conjuntoId },
          select: {
            id: true,
            descripcion: true,
            fechaInicio: true,
            fechaFin: true,
            prioridad: true,
            operarios: { select: { usuario: { select: { nombre: true } } } },
          },
          orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
        })
      : [];

    if (idsAReemplazar.length && tareasDesplazadas.length !== idsAReemplazar.length) {
      throw new Error(
        "Alguna de las tareas a reemplazar no existe o no pertenece a este conjunto.",
      );
    }

    const gerenteService = new GerenteService(this.prisma);
    const tareaPayload = {
      descripcion: excluida.descripcion,
      fechaInicio: dto.fechaInicio,
      fechaFin,
      duracionMinutos: Math.max(
        1,
        Math.round((fechaFin.getTime() - dto.fechaInicio.getTime()) / 60000),
      ),
      prioridad: excluida.prioridad,
      tipo: "CORRECTIVA",
      ubicacionId: excluida.ubicacionId,
      elementoId: excluida.elementoId,
      conjuntoId: excluida.conjuntoId,
      supervisorId: excluida.supervisorId ?? undefined,
      operariosIds: excluida.operariosIds,
    };

    const accionReemplazadas = dto.accionReemplazadas ?? "CANCELAR";

    const out = idsAReemplazar.length
      ? await gerenteService.asignarTareaConReemplazoV2({
          tarea: tareaPayload,
          reemplazarIds: idsAReemplazar,
          accionReemplazadas,
          motivoReemplazo: dto.motivoReemplazo,
        })
      : await gerenteService.asignarTarea(tareaPayload);

    if (out?.ok !== true) {
      return out;
    }

    const createdTaskId = Number(
      out?.createdCorrectivaId ?? out?.createdId ?? out?.tareaId ?? 0,
    );
    const tareaProgramadaId = createdTaskId > 0 ? createdTaskId : null;

    const reprogramadasIds: number[] = Array.isArray(out?.reprogramadasIds)
      ? out.reprogramadasIds
      : [];

    const detalleDesplazadas = tareasDesplazadas.map((tarea) => ({
      id: tarea.id,
      descripcion: tarea.descripcion,
      fechaInicio: tarea.fechaInicio.toISOString(),
      fechaFin: tarea.fechaFin.toISOString(),
      prioridad: tarea.prioridad,
      operariosNombres: tarea.operarios
        .map((operario) => operario.usuario?.nombre ?? "")
        .filter((nombre) => nombre.trim().length > 0),
      accion: reprogramadasIds.includes(tarea.id) ? "REPROGRAMADA" : "CANCELADA",
    }));

    const detalle = idsAReemplazar.length
      ? `La tarea excluida '${excluida.descripcion}' se programo como correctiva desplazando ${idsAReemplazar.length} tarea(s).`
      : `La tarea excluida '${excluida.descripcion}' se programo como correctiva en un hueco libre.`;

    const metadataJson = {
      tipoDestino: "CORRECTIVA",
      // Se mantiene el campo singular para no romper lectores antiguos del evento.
      reemplazarTareaId: idsAReemplazar[0] ?? null,
      reemplazarTareaIds: idsAReemplazar,
      accionReemplazadas,
      tareasReemplazadas: detalleDesplazadas,
      reprogramadasIds,
      canceladasIds: Array.isArray(out?.canceladasIds) ? out.canceladasIds : [],
      motivoReemplazo: dto.motivoReemplazo ?? null,
      fechaInicio: dto.fechaInicio.toISOString(),
      fechaFin: fechaFin.toISOString(),
    };

    await this.prisma.$transaction(async (tx) => {
      await tx.preventivaExcluidaBorrador.update({
        where: { id: excluida.id },
        data: {
          estado: "AGENDADA",
          tareaProgramadaId,
          resueltaEn: new Date(),
        },
      });

      await tx.preventivaBorradorEvento.create({
        data: {
          conjuntoId: excluida.conjuntoId,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          tipo: idsAReemplazar.length
            ? "EXCLUIDA_CORRECTIVA_REEMPLAZO"
            : "EXCLUIDA_CORRECTIVA_AGENDADA",
          detalle,
          excluidaId: excluida.id,
          tareaId: tareaProgramadaId,
          actorId: this.actor?.id ?? null,
          actorRol: this.actor?.rol ?? null,
          metadataJson,
        },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.EXCLUIDA,
        entidad: EntidadAuditoria.EXCLUIDA_BORRADOR,
        entidadId: excluida.id,
        accion: AccionAuditoria.PROGRAMAR_CORRECTIVA,
        conjuntoId: excluida.conjuntoId,
        actor: this.actor,
        descripcion: detalle,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        metadataJson,
      });

      if (detalleDesplazadas.length) {
        await new AuditoriaService(tx).registrarLote(
          detalleDesplazadas.map((tarea) => ({
            modulo: ModuloAuditoria.TAREA,
            entidad: EntidadAuditoria.TAREA,
            entidadId: tarea.id,
            accion: AccionAuditoria.REEMPLAZAR,
            conjuntoId: excluida.conjuntoId,
            actor: this.actor,
            descripcion: `Tarea ${tarea.accion.toLowerCase()} para dar espacio a la excluida '${excluida.descripcion}'.`,
            periodoAnio: excluida.periodoAnio,
            periodoMes: excluida.periodoMes,
            datosAntes: {
              fechaInicio: tarea.fechaInicio,
              fechaFin: tarea.fechaFin,
              prioridad: tarea.prioridad,
            },
            metadataJson: {
              excluidaId: excluida.id,
              correctivaId: tareaProgramadaId,
              accion: tarea.accion,
              motivoReemplazo: dto.motivoReemplazo ?? null,
            },
          })),
        );
      }
    });

    return {
      ...out,
      excluidaId: excluida.id,
      createdCorrectivaId: tareaProgramadaId ?? out?.createdCorrectivaId ?? null,
      tareasDesplazadas: detalleDesplazadas,
    };
  }

  /**
   * Tareas publicadas del dia que podrian desplazarse para dar espacio a una excluida,
   * con la combinacion minima (menor prioridad primero) que libera los minutos necesarios.
   */
  async listarOpcionesReemplazoExcluida(payload: unknown) {
    const dto = OpcionesReemplazoExcluidaDTO.parse(payload);
    const excluida = await this.cargarExcluidaPendiente(dto.excluidaId);

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

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        fechaInicio: { lte: finDia },
        fechaFin: { gte: inicioDia },
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        ...(excluida.operariosIds.length
          ? { operarios: { some: { id: { in: excluida.operariosIds } } } }
          : {}),
      },
      select: {
        id: true,
        descripcion: true,
        fechaInicio: true,
        fechaFin: true,
        duracionMinutos: true,
        prioridad: true,
        tipo: true,
        operarios: { select: { id: true, usuario: { select: { nombre: true } } } },
      },
      orderBy: [{ prioridad: "desc" }, { fechaInicio: "asc" }, { id: "asc" }],
    });

    const horario = await this.obtenerHorarioDia(dto.fecha);
    const minutosLibresActuales = horario
      ? this.calcularMinutosLibres(horario, tareas)
      : 0;

    const opciones = tareas.map((tarea) => ({
      tareaId: tarea.id,
      descripcion: tarea.descripcion,
      fechaInicio: tarea.fechaInicio,
      fechaFin: tarea.fechaFin,
      prioridad: tarea.prioridad,
      tipo: tarea.tipo,
      minutosQueLibera: tarea.duracionMinutos,
      operariosNombres: tarea.operarios
        .map((operario) => operario.usuario?.nombre ?? "")
        .filter((nombre) => nombre.trim().length > 0),
    }));

    const faltante = Math.max(0, excluida.duracionMinutos - minutosLibresActuales);
    const combinacionMinima: number[] = [];
    let acumulado = 0;

    if (faltante > 0) {
      for (const opcion of opciones) {
        if (acumulado >= faltante) break;
        combinacionMinima.push(opcion.tareaId);
        acumulado += opcion.minutosQueLibera;
      }
    }

    const alcanza = faltante === 0 || acumulado >= faltante;

    return {
      excluidaId: excluida.id,
      descripcion: excluida.descripcion,
      duracionMinutos: excluida.duracionMinutos,
      fecha: inicioDia,
      minutosLibresActuales,
      minutosFaltantes: faltante,
      opciones,
      combinacionMinima: alcanza ? combinacionMinima : [],
      minutosCombinacionMinima: alcanza ? acumulado : 0,
      alcanzaConDesplazamientos: alcanza,
    };
  }

  /**
   * Cambia el operario de una tarea excluida del cronograma publicado como excepcion puntual:
   * no toca la definicion preventiva, asi que no afecta a los periodos siguientes.
   */
  async reasignarOperarioExcluidaPublicada(payload: unknown) {
    const dto = ReasignarOperarioExcluidaPublicadaDTO.parse(payload);
    const excluida = await this.cargarExcluidaPendiente(dto.excluidaId);

    const hayPublicado = await this.existeCronogramaPreventivoPublicado(
      excluida.periodoAnio,
      excluida.periodoMes,
    );
    if (!hayPublicado) {
      throw new Error(
        "Solo se puede reasignar el operario cuando el cronograma del periodo ya esta publicado.",
      );
    }

    const nuevoOperarioId = dto.nuevoOperarioId.trim();

    const operario = await this.prisma.operario.findUnique({
      where: { id: nuevoOperarioId },
      select: { id: true, usuario: { select: { nombre: true } } },
    });
    if (!operario) {
      throw new Error("El operario seleccionado no existe.");
    }

    const disponibilidad = await validarOperariosDisponiblesEnFecha({
      prisma: this.prisma,
      fecha: excluida.fechaObjetivo,
      operariosIds: [nuevoOperarioId],
    });
    if (!disponibilidad.ok) {
      throw new Error(
        `${operario.usuario?.nombre ?? "El operario"} no trabaja el dia objetivo de esta tarea.`,
      );
    }

    const tieneEspacio = await this.tieneVentanaLibre({
      operarioId: nuevoOperarioId,
      fecha: excluida.fechaObjetivo,
      duracionMinutos: excluida.duracionMinutos,
    });
    if (!tieneEspacio) {
      throw new Error(
        `${operario.usuario?.nombre ?? "El operario"} no tiene horas libres suficientes ese dia para asumir esta tarea.`,
      );
    }

    const nombreOperario = operario.usuario?.nombre ?? null;
    const metadataActual = metadataComoObjeto(excluida.metadataJson);
    const excepcionOperario = {
      operariosOriginalesIds: excluida.operariosIds,
      operariosOriginalesNombres: excluida.operariosNombres,
      nuevoOperarioId,
      nuevoOperarioNombre: nombreOperario,
      motivo: dto.motivo ?? null,
      aplicadoEn: new Date().toISOString(),
    };

    const detalle = `Se asigno a ${nombreOperario ?? nuevoOperarioId} como excepcion para la tarea excluida '${excluida.descripcion}'. No cambia el plan preventivo.`;

    const actualizada = await this.prisma.$transaction(async (tx) => {
      const row = await tx.preventivaExcluidaBorrador.update({
        where: { id: excluida.id },
        data: {
          operariosIds: [nuevoOperarioId],
          operariosNombres: nombreOperario ? [nombreOperario] : [],
          metadataJson: {
            ...metadataActual,
            excepcionOperario,
          } as Prisma.InputJsonValue,
        },
      });

      await tx.preventivaBorradorEvento.create({
        data: {
          conjuntoId: excluida.conjuntoId,
          periodoAnio: excluida.periodoAnio,
          periodoMes: excluida.periodoMes,
          tipo: "EXCLUIDA_OPERARIO_EXCEPCION",
          detalle,
          excluidaId: excluida.id,
          actorId: this.actor?.id ?? null,
          actorRol: this.actor?.rol ?? null,
          metadataJson: excepcionOperario as Prisma.InputJsonValue,
        },
      });

      await new AuditoriaService(tx).registrar({
        modulo: ModuloAuditoria.EXCLUIDA,
        entidad: EntidadAuditoria.EXCLUIDA_BORRADOR,
        entidadId: excluida.id,
        accion: AccionAuditoria.REASIGNAR_OPERARIO,
        conjuntoId: excluida.conjuntoId,
        actor: this.actor,
        descripcion: detalle,
        periodoAnio: excluida.periodoAnio,
        periodoMes: excluida.periodoMes,
        datosAntes: {
          operariosIds: excluida.operariosIds,
          operariosNombres: excluida.operariosNombres,
        },
        datosDespues: {
          operariosIds: [nuevoOperarioId],
          operariosNombres: nombreOperario ? [nombreOperario] : [],
        },
        metadataJson: excepcionOperario,
      });

      return row;
    });

    return { ok: true, excluida: actualizada, esExcepcion: true };
  }

  /**
   * Informe de excluidas del periodo: cuales se programaron despues, que tareas se
   * desplazaron para lograrlo, que excepciones de operario se aplicaron y cuales siguen pendientes.
   */
  async informeExcluidasDelPeriodo(payload: unknown) {
    const dto = InformeExcluidasDTO.parse(payload);

    const [eventos, excluidas] = await Promise.all([
      this.prisma.preventivaBorradorEvento.findMany({
        where: {
          conjuntoId: this.conjuntoId,
          periodoAnio: dto.anio,
          periodoMes: dto.mes,
          tipo: {
            in: [
              "EXCLUIDA_CORRECTIVA_AGENDADA",
              "EXCLUIDA_CORRECTIVA_REEMPLAZO",
              "EXCLUIDA_OPERARIO_EXCEPCION",
            ],
          },
        },
        orderBy: [{ creadoEn: "asc" }, { id: "asc" }],
      }),
      this.prisma.preventivaExcluidaBorrador.findMany({
        where: {
          conjuntoId: this.conjuntoId,
          periodoAnio: dto.anio,
          periodoMes: dto.mes,
        },
        orderBy: [{ prioridad: "asc" }, { fechaObjetivo: "asc" }, { id: "asc" }],
      }),
    ]);

    const porId = new Map(excluidas.map((item) => [item.id, item]));
    const nombresActores = await this.resolverNombresActores(
      eventos.map((evento) => evento.actorId),
    );

    const programadasPosteriormente: Record<string, any>[] = [];
    const excepcionesOperario: Record<string, any>[] = [];

    for (const evento of eventos) {
      const excluida = evento.excluidaId != null ? porId.get(evento.excluidaId) : undefined;
      const metadata = metadataComoObjeto(evento.metadataJson);
      const actor = {
        id: evento.actorId,
        rol: evento.actorRol,
        nombre: evento.actorId ? (nombresActores.get(evento.actorId) ?? null) : null,
      };

      if (evento.tipo === "EXCLUIDA_OPERARIO_EXCEPCION") {
        excepcionesOperario.push({
          excluidaId: evento.excluidaId,
          descripcion: excluida?.descripcion ?? null,
          operariosOriginales: metadata.operariosOriginalesNombres ?? [],
          operariosNuevos: metadata.nuevoOperarioNombre
            ? [metadata.nuevoOperarioNombre]
            : [],
          motivo: metadata.motivo ?? null,
          fecha: evento.creadoEn,
          actor,
        });
        continue;
      }

      programadasPosteriormente.push({
        excluidaId: evento.excluidaId,
        descripcion: excluida?.descripcion ?? null,
        tareaId: evento.tareaId,
        fechaProgramada: metadata.fechaInicio ?? null,
        fechaFinProgramada: metadata.fechaFin ?? null,
        operariosNombres: excluida?.operariosNombres ?? [],
        tareasDesplazadas: Array.isArray(metadata.tareasReemplazadas)
          ? metadata.tareasReemplazadas
          : [],
        motivo: metadata.motivoReemplazo ?? null,
        fecha: evento.creadoEn,
        actor,
      });
    }

    return {
      anio: dto.anio,
      mes: dto.mes,
      programadasPosteriormente,
      excepcionesOperario,
      pendientes: excluidas
        .filter((item) => item.estado === "PENDIENTE")
        .map((item) => ({
          excluidaId: item.id,
          descripcion: item.descripcion,
          frecuencia: item.frecuencia,
          diaSemanaProgramado: item.diaSemanaProgramado,
          prioridad: item.prioridad,
          duracionMinutos: item.duracionMinutos,
          fechaObjetivo: item.fechaObjetivo,
          motivoTipo: item.motivoTipo,
          motivoMensaje: item.motivoMensaje,
          operariosNombres: item.operariosNombres,
        })),
    };
  }

  /* ==================== Helpers de excluidas ==================== */

  private async cargarExcluidaPendiente(excluidaId: number) {
    const excluida = await this.prisma.preventivaExcluidaBorrador.findUnique({
      where: { id: excluidaId },
    });

    if (!excluida || excluida.conjuntoId !== this.conjuntoId) {
      throw new Error("La tarea excluida no existe para este conjunto.");
    }
    if (excluida.estado !== "PENDIENTE") {
      throw new Error("La tarea excluida ya no esta disponible para programar.");
    }

    return excluida;
  }

  private async resolverNombresActores(actorIds: (string | null)[]) {
    const ids = Array.from(
      new Set(actorIds.filter((id): id is string => typeof id === "string" && id.length > 0)),
    );
    if (!ids.length) return new Map<string, string>();

    const usuarios = await this.prisma.usuario.findMany({
      where: { id: { in: ids } },
      select: { id: true, nombre: true },
    });

    return new Map(usuarios.map((usuario) => [usuario.id, usuario.nombre]));
  }

  private async obtenerHorarioDia(fecha: Date) {
    const horario = await this.prisma.conjuntoHorario.findFirst({
      where: { conjuntoId: this.conjuntoId, dia: dateToDiaSemana(fecha) },
    });
    if (!horario) return null;

    return {
      startMin: toMin(horario.horaApertura),
      endMin: toMin(horario.horaCierre),
      descansoStartMin: horario.descansoInicio ? toMin(horario.descansoInicio) : null,
      descansoEndMin: horario.descansoFin ? toMin(horario.descansoFin) : null,
    };
  }

  private calcularMinutosLibres(
    horario: HorarioDiaConjunto,
    tareas: { fechaInicio: Date; fechaFin: Date }[],
  ): number {
    const bloqueos = bloqueosPorDescanso(horario);

    const ocupados: Intervalo[] = tareas.map((tarea) => ({
      i: toMinOfDay(tarea.fechaInicio),
      f: toMinOfDay(tarea.fechaFin),
    }));

    const bloqueado = mergeIntervalos([
      ...ocupados,
      ...bloqueos.map((bloqueo) => ({ i: bloqueo.startMin, f: bloqueo.endMin })),
    ]);

    return freeFromOccupied(horario.startMin, horario.endMin, bloqueado).reduce(
      (total, libre) => total + Math.max(0, libre.f - libre.i),
      0,
    );
  }

  private async tieneVentanaLibre(params: {
    operarioId: string;
    fecha: Date;
    duracionMinutos: number;
  }): Promise<boolean> {
    const horario = await this.obtenerHorarioDia(params.fecha);
    if (!horario) return false;

    const bloqueos = bloqueosPorDescanso(horario);

    const agenda = await buildAgendaPorOperarioDia({
      prisma: this.prisma,
      conjuntoId: this.conjuntoId,
      fechaDia: params.fecha,
      operariosIds: [params.operarioId],
      incluirBorrador: false,
      bloqueosGlobales: bloqueos,
      excluirEstados: ["PENDIENTE_REPROGRAMACION"],
    });

    const ocupados = mergeIntervalos(agenda[params.operarioId] ?? []);

    return (
      buscarHuecoDiaConSplitEarliest({
        startMin: horario.startMin,
        endMin: horario.endMin,
        durMin: params.duracionMinutos,
        ocupados,
        bloqueos,
        desiredStartMin: horario.startMin,
        maxBloques: 3,
      }) != null
    );
  }

  async eliminarCronogramaPublicado(payload: unknown) {
    const { anio, mes } = EliminarCronogramaPublicadoDTO.parse(payload);
    const inicioMes = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
    const finMes = new Date(anio, mes, 0, 23, 59, 59, 999);

    const tareas = await this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        OR: [
          {
            periodoAnio: anio,
            periodoMes: mes,
          },
          {
            periodoAnio: null,
            periodoMes: null,
            fechaFin: { gte: inicioMes },
            fechaInicio: { lte: finMes },
          },
        ],
      },
      select: { id: true, estado: true, periodoAnio: true, periodoMes: true },
      orderBy: [{ fechaInicio: "desc" }, { id: "desc" }],
    });

    if (!tareas.length) {
      return { ok: true, eliminadas: 0 };
    }

    const tareasBloqueadas = tareas.filter(
      (tarea) =>
        tarea.estado === EstadoTarea.COMPLETADA ||
        tarea.estado === EstadoTarea.PENDIENTE_APROBACION,
    );

    if (tareasBloqueadas.length > 0) {
      throw new Error(
        "No se puede eliminar el cronograma porque tiene tareas completadas o pendientes de aprobacion.",
      );
    }

    const tareaIds = tareas.map((tarea) => tarea.id);

    for (const tareaId of tareaIds) {
      await this.eliminarTareaPublicada(tareaId);
    }

    const restantes = await this.prisma.tarea.count({
      where: { id: { in: tareaIds } },
    });

    const eliminadas = tareaIds.length - restantes;

    if (restantes > 0) {
      throw new Error(
        "No se pudo eliminar completamente el cronograma publicado.",
      );
    }

    await this.auditoria.registrar({
      modulo: ModuloAuditoria.CRONOGRAMA,
      entidad: EntidadAuditoria.CRONOGRAMA_PERIODO,
      entidadId: `${this.conjuntoId}-${anio}-${mes}`,
      accion: AccionAuditoria.ELIMINAR_CRONOGRAMA,
      conjuntoId: this.conjuntoId,
      actor: this.actor,
      descripcion: `Se elimino el cronograma publicado de ${mes}/${anio} (${eliminadas} tarea(s)).`,
      periodoAnio: anio,
      periodoMes: mes,
      metadataJson: { eliminadas, tareaIds },
    });

    return { ok: true, eliminadas };
  }

  async tareasPorOperario(payload: unknown) {
    const { operarioId } = OperarioIdDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        operarios: { some: { id: operarioId.toString() } },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async tareasPorFecha(payload: unknown) {
    const { fecha } = FechaDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        fechaInicio: { lte: fecha },
        fechaFin: { gte: fecha },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });
  }

  async tareasEnRango(payload: unknown) {
    const { fechaInicio, fechaFin } = RangoFechasDTO.parse(payload);
    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        // solape de rangos
        fechaFin: { gte: fechaInicio },
        fechaInicio: { lte: fechaFin },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
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
        borrador: false,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        // según tu versión de Prisma, podrías necesitar { is: { nombre: ... } }
        ubicacion: { nombre: { equals: ubicacion, mode: "insensitive" } },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
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
      fechaInicio = new Date(
        d0.getFullYear(),
        d0.getMonth(),
        d0.getDate(),
        0,
        0,
        0,
        0
      );
      fechaFin = new Date(
        d0.getFullYear(),
        d0.getMonth(),
        d0.getDate(),
        23,
        59,
        59,
        999
      );
    } else {
      fechaInicio = f.fechaInicio ?? undefined;
      fechaFin = f.fechaFin ?? undefined;
    }

    return this.prisma.tarea.findMany({
      where: {
        conjuntoId: this.conjuntoId,
        borrador: false,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        operarios: f.operarioId
          ? { some: { id: f.operarioId.toString() } }
          : undefined,
        fechaInicio: fechaFin ? { lte: fechaFin } : undefined,
        fechaFin: fechaInicio ? { gte: fechaInicio } : undefined,
        ubicacion: f.ubicacion
          ? { nombre: { equals: f.ubicacion, mode: "insensitive" } }
          : undefined,
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
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
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        fechaFin: { gte: inicioDia },
        fechaInicio: { lte: finDia },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
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
            elemento: construirRutaElemento(t.elemento as any) ?? null,
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
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        fechaFin: { gte: lunes },
        fechaInicio: { lte: domingo },
      },
      include: {
        operarios: { include: { usuario: true } },
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
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
              elemento: construirRutaElemento(t.elemento as any) ?? null,
              desde: t.fechaInicio,
              hasta: t.fechaFin,
            });
          }
        }
      }
    }

    return dias;
  }

  async sugerirOperarios(payload: unknown) {
    const { fechaInicio, fechaFin, max, requiereFuncion } =
      SugerirDTO.parse(payload);

    // 1) Traer operarios del conjunto
    const operarios = await this.prisma.operario.findMany({
      where: {
        conjuntos: { some: { nit: this.conjuntoId } },
        ...(requiereFuncion
          ? { funciones: { has: requiereFuncion as any } }
          : {}),
      },
      include: { usuario: true },
    });
    if (operarios.length === 0) return [];

    // 2) Calcular horas ya asignadas
    const out: Array<{
      id: string; // <- antes number
      nombre: string;
      horasSemana: number;
      solapa: boolean;
    }> = [];

    for (const op of operarios) {
      const lunes = mondayOfWeek(fechaInicio);
      const domingo = new Date(lunes);
      domingo.setDate(lunes.getDate() + 6);

      const tareasSemana = await this.prisma.tarea.findMany({
        where: {
          conjuntoId: this.conjuntoId,
          operarios: { some: { id: op.id } }, // op.id es string
          fechaFin: { gte: lunes },
          fechaInicio: { lte: domingo },
        },
        select: { fechaInicio: true, fechaFin: true, duracionMinutos: true },
      });

      const horas = tareasSemana.reduce(
        (acc, t) => acc + (t.duracionMinutos ?? 0),
        0
      );
      const solapa = tareasSemana.some(
        (t) => t.fechaInicio <= fechaFin && fechaInicio <= t.fechaFin
      );

      out.push({
        id: op.id, // ya es string, no hace falta toString()
        nombre: op.usuario.nombre,
        horasSemana: horas,
        solapa,
      });
    }

    // 3) Ranking
    out.sort((a, b) => {
      if (a.solapa !== b.solapa) return a.solapa ? 1 : -1;
      return a.horasSemana - b.horasSemana;
    });

    return out.slice(0, max);
  }

  async calendarioMensual(params: {
    anio: number;
    mes: number;
    operarioId?: number;
    tipo?: "PREVENTIVA" | "CORRECTIVA" | "TODAS";
    borrador?: boolean;
  }) {
    const { anio, mes, operarioId, tipo, borrador } = params;
    const start = new Date(anio, mes - 1, 1, 0, 0, 0, 0);
    const end = new Date(anio, mes, 0, 23, 59, 59, 999); // último día del mes

    const where: any = {
      conjuntoId: this.conjuntoId,
      estado: { notIn: ESTADOS_NO_CRONOGRAMA },
      fechaFin: { gte: start },
      fechaInicio: { lte: end },
    };
    if (operarioId) where.operarios = { some: { id: operarioId } };
    if (borrador !== undefined) where.borrador = borrador;
    if (tipo && tipo !== "TODAS") where.tipo = tipo;

    const tareas = await this.prisma.tarea.findMany({
      where,
      select: { fechaInicio: true, fechaFin: true, tipo: true },
    });

    // bucket por día (1..31)
    const daysInMonth = new Date(anio, mes, 0).getDate();
    const dias = Array.from({ length: daysInMonth }, (_, i) => {
      const fecha = new Date(anio, mes - 1, i + 1);
      return {
        dia: i + 1,
        fecha: dateKeyLocal(fecha),
        nombreDia: WEEKDAY_NAMES_ES[fecha.getDay()],
        total: 0,
        preventivas: 0,
        correctivas: 0,
      };
    });

    for (const t of tareas) {
      // marca todos los días que toca (por si cruza)
      const cur = new Date(Math.max(+t.fechaInicio, +start));
      cur.setHours(0, 0, 0, 0);
      const last = new Date(Math.min(+t.fechaFin, +end));
      last.setHours(0, 0, 0, 0);
      while (cur <= last) {
        const d = cur.getDate();
        const slot = dias[d - 1];
        slot.total++;
        if (t.tipo === "PREVENTIVA") slot.preventivas++;
        else slot.correctivas++;
        cur.setDate(cur.getDate() + 1);
      }
    }

    const totalesMes = {
      total: dias.reduce((a, d) => a + d.total, 0),
      preventivas: dias.reduce((a, d) => a + d.preventivas, 0),
      correctivas: dias.reduce((a, d) => a + d.correctivas, 0),
    };

    return { anio, mes, dias, totalesMes };
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
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
        operarios: { some: { id: operarioId.toString() } },
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

    const esFestivo = await isFestivoDate({
      prisma: this.prisma,
      fecha: fechaInicio,
      pais: "CO",
    });
    if (esFestivo) {
      throw new Error("No se permite reprogramar tareas a festivos.");
    }

    const tarea = await this.prisma.tarea.findUnique({
      where: { id: tareaId },
      select: { operarios: { select: { id: true } } },
    });
    const operariosIds = tarea?.operarios.map((o) => o.id) ?? [];
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
      const duracionMinutos = Math.max(
        1,
        Math.round((fechaFin.getTime() - fechaInicio.getTime()) / 60000),
      );
      const limite = await validarLimiteSemanalOperarios({
        prisma: this.prisma,
        conjuntoId: this.conjuntoId,
        operariosIds,
        fechaInicio,
        duracionMinutos,
        excluirTareaId: tareaId,
      });
      if (!limite.ok) {
        throw new Error(
          `Los operarios ${limite.excedidos.join(", ")} superan su limite semanal con esta reprogramacion.`,
        );
      }
    }

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
      where: {
        conjuntoId: this.conjuntoId,
        estado: { notIn: ESTADOS_NO_CRONOGRAMA },
      },
      include: {
        ubicacion: true,
        elemento: { include: elementoParentChainInclude },
        operarios: { include: { usuario: true } },
      },
      orderBy: [{ fechaInicio: "asc" }, { id: "asc" }],
    });

    return tareas.map((t) => {
      const nombresOperarios =
        t.operarios
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
          elemento: construirRutaElemento(t.elemento as any) ?? null,
        },
      };
    });
  }
}
